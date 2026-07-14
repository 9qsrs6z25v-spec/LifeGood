import SwiftUI
import PhotosUI
import UIKit

// MARK: - 相機選取器（UIImagePickerController 包裝）

struct CameraPicker: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 美化紀錄（RenovationPhotoEditor / RenovationStackViewer）
// [2026-06] 第一次美化方向：
//   1. renoSectionHeader 輔助：統一三個 Section（基本資訊 / 照片 / 備註）標題列，
//      升級為 4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.bold，
//      對齊全 App AddVehicleView / AddStockView section header 設計語言。
//   2. 照片 Section header：加入彩色計數膠囊（teal Capsule 徽章），
//      對齊 MultiPhotoGallery.title header count badge 規格。
//   3. RenovationStackViewer 頁碼：從純 .caption2 文字升級為白色半透明 Capsule 膠囊徽章，
//      對齊全 App 計數膠囊規格（IncomeView.daySectionHeader 等），暗背景下更醒目。
//   4. RenovationStackViewer 日期：加入 calendar 圖示前綴，
//      與全 App 日期 icon+text 設計語言統一（CareerView / SubordinateView 等）。
//
// [2026-07 v2] 修正一致性問題 + 空狀態補齊：
//   1. 照片 Section header：發現第一次美化把它做成獨立的漸層色條 + icon + 標題 +
//      計數膠囊，但 MultiPhotoGallery 元件本身「內建」一列一模一樣資訊的標題列
//      （bold 標題 + 綠色計數膠囊 + 新增選單按鈕，見 MultiPhotoGallery.swift body 開頭）。
//      結果同一頁「照片」文字與筆數重複顯示兩次（Form 灰底小標題 + 元件內建 header）。
//      比對全 App 其他呼叫端（AddExpenseView.photoGallerySection／FixedExpenseView.photoSection）
//      都只用純文字 `Text("照片")` 當 Section header，把裝飾留給元件內建 header 負責——
//      改回同樣做法，消除重複視覺雜訊。**下次若要幫 MultiPhotoGallery 呼叫端加裝飾 header，
//      記得元件本身已經有一份，不要重複疊加。**
//   2. RenovationStackViewer 空狀態「沒有照片」：從純文字升級為圖示 + 文字直式排版
//      （semi-transparent 圓形圖示徽章 + 說明文字），對齊全 App 空狀態慣例
//      （MultiPhotoGallery.emptyState 同款結構，僅配色改為白色系以搭配黑底全螢幕）。

// MARK: - 裝潢照片編輯器（支援多張照片）

struct RenovationPhotoEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: RenovationPhoto?
    /// 預先帶入的檔名清單（批次匯入時由 RealEstateDetailView 提供）
    let preloadedFileNames: [String]

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileNames: [String] = []
    @State private var showDeleteConfirm: Bool = false

    init(estateId: UUID, editing: RenovationPhoto?, preloadedFileNames: [String] = []) {
        self.estateId = estateId
        self.editing = editing
        self.preloadedFileNames = preloadedFileNames
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題（例：客廳油漆、廚房磁磚）", text: $title)
                } header: {
                    renoSectionHeader("基本資訊", icon: "calendar.circle.fill",
                                      gradient: [Color(red: 0.42, green: 0.30, blue: 0.92),
                                                 Color(red: 0.30, green: 0.18, blue: 0.75)])
                }

                Section {
                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { RenovationPhoto.photoURL(for: $0) },
                        onSaveImage: { data in
                            RenovationPhoto.savePhoto(data, id: UUID())
                        },
                        onDeleteFile: { name in
                            RenovationPhoto.deletePhoto(name)
                        },
                        title: "照片"
                    )
                    .padding(.vertical, 4)
                } header: {
                    // 純文字標題：裝飾（標題／計數）已由 MultiPhotoGallery 內建 header 負責，
                    // 這裡疊加同樣資訊會造成重複顯示，對齊 AddExpenseView / FixedExpenseView 做法。
                    Text("照片")
                } footer: {
                    Text("可拍照或從相簿一次選多張，會以堆疊方式顯示在裝潢照片廊中。")
                }

                Section {
                    TextField("選填備註（例：師傅電話、廠商）", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    renoSectionHeader("備註", icon: "note.text",
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
            .navigationTitle(editing == nil ? "新增裝潢照片" : "編輯裝潢照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { cancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(photoFileNames.isEmpty)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { setupInitial() }
        }
    }

    // MARK: - 輔助

    /// 美化：統一 Section header（4pt Capsule 漸層色條 + 彩色圖示 + .subheadline.bold），
    /// 對齊全 App AddVehicleView / AddStockView section header 設計語言。
    private func renoSectionHeader(_ title: String, icon: String, gradient: [Color]) -> some View {
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

    // MARK: - 初始化

    private func setupInitial() {
        if let e = editing {
            date = e.date
            title = e.title
            note = e.note
            photoFileNames = e.photoFileNames
        } else if !preloadedFileNames.isEmpty {
            photoFileNames = preloadedFileNames
        }
    }

    // MARK: - 動作

    private func save() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let recordId = editing?.id ?? UUID()

        let record = RenovationPhoto(
            id: recordId,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileName: nil,
            photoFileNames: photoFileNames,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        if let idx = estate.renovationPhotos.firstIndex(where: { $0.id == recordId }) {
            estate.renovationPhotos[idx] = record
        } else {
            estate.renovationPhotos.append(record)
        }
        // 先關閉 sheet，下一個 runloop 才改動 @Published store。避免在「關閉 sheet」的
        // view-update 交易裡同步改 observed state（父頁堆了多個 sheet），真機上會閃退。
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }

    /// 取消時只清除本次 session 新增、尚未存檔的檔案；「原本就有」的基準線視新增／編輯模式而定：
    /// 新增模式是呼叫端傳入的 preloadedFileNames，編輯模式則是 editing 進來時的 e.photoFileNames——
    /// 過去編輯模式完全不清檔案（只判斷 editing == nil），使用者編輯既有紀錄時新加照片後按取消，
    /// 該照片檔會留在磁碟／iCloud 卻不再被任何紀錄引用，變成永久孤兒檔案。
    private func cancel() {
        let original = Set(editing?.photoFileNames ?? preloadedFileNames)
        for name in photoFileNames where !original.contains(name) {
            RenovationPhoto.deletePhoto(name)
        }
        dismiss()
    }

    private func deleteRecord() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        // 刪除目前畫面上仍列出的 photoFileNames（即時狀態），而非 e.photoFileNames 這份進入編輯畫面時
        // 的舊快照：編輯過程中新增的照片只存在於 photoFileNames，用舊快照刪除會漏刪這些孤兒檔案
        // （使用者移除照片時 MultiPhotoGallery 的 onDeleteFile 已即時刪檔並同步移出 photoFileNames，
        // 不會重複刪除已移除的項目）。
        for name in photoFileNames {
            RenovationPhoto.deletePhoto(name)
        }
        estate.renovationPhotos.removeAll { $0.id == e.id }
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }
}

// MARK: - 堆疊展開瀏覽器

/// 把一筆 RenovationPhoto 中所有照片以左右滑動的方式逐張展開。
/// 黑底全螢幕，下方半透明面板顯示日期 / 標題 / 備註。
struct RenovationStackViewer: View {
    let record: RenovationPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if record.photoFileNames.isEmpty {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 52, height: 52)
                            Circle()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                .frame(width: 52, height: 52)
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Text("沒有照片")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(record.photoFileNames.enumerated()), id: \.offset) { idx, name in
                            let url = RenovationPhoto.photoURL(for: name)
                            AsyncLocalImage(url: url) { img, _ in
                                ZStack {
                                    if let img {
                                        ZoomableImageView(image: img)
                                    } else {
                                        ProgressView().tint(.white)
                                    }
                                }
                            }
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }

                VStack {
                    Spacer()
                    if !record.title.isEmpty || !record.note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.title.isEmpty ? "未命名" : record.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                // 頁碼升級為半透明 Capsule 膠囊徽章（對齊全 App 計數膠囊規格）
                                Text("\(currentIndex + 1) / \(record.photoFileNames.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.90))
                                    .padding(.horizontal, 9).padding(.vertical, 3)
                                    .background(.white.opacity(0.20))
                                    .clipShape(Capsule())
                            }
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(3)
                            }
                            // 日期加 calendar 圖示前綴（對齊全 App 日期 icon+text 語言）
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10, weight: .medium))
                                Text(fmtDate(record.date))
                                    .font(.caption2)
                            }
                            .foregroundStyle(.white.opacity(0.65))
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(record.title.isEmpty ? "裝潢照片" : record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func fmtDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
