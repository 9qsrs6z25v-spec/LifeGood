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

// MARK: - 裝潢照片編輯器

struct RenovationPhotoEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: RenovationPhoto?

    @State private var date: Date = Date()
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var photoFileName: String?
    @State private var pendingImageData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera: Bool = false
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("標題（例：客廳油漆、廚房磁磚）", text: $title)
                }

                Section {
                    if let data = pendingImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let url = currentPhotoURL, let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Menu {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                        }
                        // PhotosPicker 不能直接放在 Menu 裡（無 sheet 環境），改用 state 觸發
                        Button {
                            isPresentingPhotoPicker = true
                        } label: {
                            Label("從相簿選取", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text(pendingImageData != nil || photoFileName != nil ? "更換照片" : "新增照片")
                            Spacer()
                            if pendingImageData != nil || photoFileName != nil {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    if pendingImageData != nil || photoFileName != nil {
                        Button(role: .destructive) {
                            pendingImageData = nil
                            if let name = photoFileName { RenovationPhoto.deletePhoto(name) }
                            photoFileName = nil
                        } label: {
                            Label("移除照片", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("照片")
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
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    pendingImageData = image.jpegData(compressionQuality: 0.85)
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await MainActor.run { pendingImageData = data }
                }
            }
            .onAppear {
                if let e = editing {
                    date = e.date
                    title = e.title
                    note = e.note
                    photoFileName = e.photoFileName
                }
            }
        }
    }

    @State private var isPresentingPhotoPicker: Bool = false

    private var currentPhotoURL: URL? {
        guard let name = photoFileName else { return nil }
        return RenovationPhoto.photosDirectory.appendingPathComponent(name)
    }

    // MARK: - 動作

    private func save() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        let recordId = editing?.id ?? UUID()

        // 若有新拍照 / 新選的照片，存檔並更新 fileName
        if let data = pendingImageData {
            // 先刪舊檔（避免孤兒）
            if let oldName = photoFileName { RenovationPhoto.deletePhoto(oldName) }
            photoFileName = RenovationPhoto.savePhoto(data, id: recordId)
        }

        let record = RenovationPhoto(
            id: recordId,
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            photoFileName: photoFileName,
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

    private func deleteRecord() {
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        if let name = e.photoFileName { RenovationPhoto.deletePhoto(name) }
        estate.renovationPhotos.removeAll { $0.id == e.id }
        store.update(estate)
        dismiss()
    }
}
