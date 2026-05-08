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
                Section("基本資訊") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題（例：客廳油漆、廚房磁磚）", text: $title)
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
                    Text("照片（\(photoFileNames.count) 張）")
                } footer: {
                    Text("可拍照或從相簿一次選多張，會以堆疊方式顯示在裝潢照片廊中。")
                }

                Section("備註") {
                    TextField("選填備註（例：師傅電話、廠商）", text: $note, axis: .vertical).lineLimit(3)
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
        store.update(estate)
        dismiss()
    }

    /// 取消時若是新增模式，把已寫入的檔案清掉避免變孤兒
    private func cancel() {
        if editing == nil {
            // 編輯既有時不清，因為原本就在硬碟上
            for name in photoFileNames {
                RenovationPhoto.deletePhoto(name)
            }
        }
        dismiss()
    }

    private func deleteRecord() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        for name in e.photoFileNames {
            RenovationPhoto.deletePhoto(name)
        }
        estate.renovationPhotos.removeAll { $0.id == e.id }
        store.update(estate)
        dismiss()
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
                    Text("沒有照片")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(record.photoFileNames.enumerated()), id: \.offset) { idx, name in
                            let url = RenovationPhoto.photoURL(for: name)
                            ZStack {
                                if let img = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    ProgressView().tint(.white)
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
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(currentIndex + 1) / \(record.photoFileNames.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(3)
                            }
                            Text(fmtDate(record.date))
                                .font(.caption2)
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

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
