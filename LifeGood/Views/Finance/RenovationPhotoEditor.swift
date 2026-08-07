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

// MARK: - 連拍相機（自訂快門，可連續拍多張，按「完成」才離開）
//
// UIImagePickerController 預設相機介面拍一張就得離開；改用官方支援多拍的做法：
// showsCameraControls = false + cameraOverlayView 自訂快門呼叫 takePicture()，
// didFinishPicking 回呼後不 dismiss，鏡頭回到即時預覽即可再拍下一張。
// 每拍一張立即回傳 onPicked（呼叫端存檔→ImageCompressor 壓縮→PhotoCloudSync 上傳）。
// 裝置無相機（模擬器）時退回相簿選取，行為同 CameraPicker。

struct MultiShotCameraPicker: UIViewControllerRepresentable {
    /// 每拍成一張呼叫一次
    var onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.showsCameraControls = false
            // 4:3 相機預覽預設貼齊畫面頂部，下方到控制列之間留大片黑區；
            // 往下平移讓預覽在「畫面頂部～控制列」之間垂直置中，畫面較平衡
            let screen = UIScreen.main.bounds
            let previewHeight = screen.width * 4.0 / 3.0
            let controlsHeight: CGFloat = 130
            let visibleHeight = screen.height - controlsHeight
            if previewHeight < visibleHeight {
                picker.cameraViewTransform = CGAffineTransform(
                    translationX: 0, y: (visibleHeight - previewHeight) / 2
                )
            }
            let overlay = MultiShotOverlayView(frame: UIScreen.main.bounds)
            overlay.onShutter = { [weak picker] in picker?.takePicture() }
            overlay.onDone = { context.coordinator.finish() }
            picker.cameraOverlayView = overlay
            context.coordinator.overlay = overlay
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MultiShotCameraPicker
        weak var overlay: MultiShotOverlayView?
        private var shotCount = 0
        init(_ parent: MultiShotCameraPicker) { self.parent = parent }

        func finish() { parent.dismiss() }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPicked(image)
                shotCount += 1
                overlay?.setCount(shotCount)
            }
            // 相簿後援模式（無相機）沒有 overlay：選完一張即離開，行為同 CameraPicker
            if picker.sourceType != .camera { parent.dismiss() }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// 連拍相機的自訂控制列：底部黑色半透明橫條（取消｜快門｜完成 N 張）。
final class MultiShotOverlayView: UIView {
    var onShutter: (() -> Void)?
    var onDone: (() -> Void)?

    private let doneButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let bar = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // 跟隨父視圖尺寸（旋轉／不同機型），避免固定 UIScreen bounds 與實際畫面不符
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        bar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        // 快門：68pt 白圈 + 內圓
        let shutter = UIButton(type: .custom)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.layer.cornerRadius = 34
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.cgColor
        let inner = UIView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.backgroundColor = .white
        inner.layer.cornerRadius = 27
        inner.isUserInteractionEnabled = false
        shutter.addSubview(inner)
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bar.addSubview(shutter)

        doneButton.setTitle("完成", for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        bar.addSubview(doneButton)

        countLabel.text = ""
        countLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(countLabel)

        // 先前把整條控制列釘在 view 最底、高度固定 130，快門/完成鈕落在 Home indicator
        // 手勢區內被切掉一半。改為「快門底部錨定 safeAreaLayoutGuide.bottom」，控制列
        // 高度由內容撐開、背景仍延伸到螢幕最底（蓋住 Home indicator 區域的黑底）。
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.topAnchor.constraint(equalTo: shutter.topAnchor, constant: -14),

            shutter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shutter.widthAnchor.constraint(equalToConstant: 68),
            shutter.heightAnchor.constraint(equalToConstant: 68),
            inner.centerXAnchor.constraint(equalTo: shutter.centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 54),
            inner.heightAnchor.constraint(equalToConstant: 54),

            doneButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24),
            doneButton.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            countLabel.centerYAnchor.constraint(equalTo: shutter.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 只讓控制列吃事件，其餘區域穿透給相機預覽（避免蓋住對焦手勢）；
    /// 以實際排版後的 bar.frame 判斷，不再用固定 130pt 推算。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bar.frame == .zero ? false : bar.frame.contains(point)
    }

    func setCount(_ n: Int) {
        countLabel.text = n > 0 ? "已拍 \(n) 張" : ""
        doneButton.setTitle(n > 0 ? "完成(\(n))" : "完成", for: .normal)
    }

    @objc private func shutterTapped() { onShutter?() }
    @objc private func doneTapped() { onDone?() }
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
//
// [2026-07 v3] 大圖載入淡入動畫：
//   • RenovationStackViewer 逐張展開的大圖原本 AsyncLocalImage 一讀到檔案就直接把
//     ZoomableImageView 硬切換上畫面，與同檔案（MultiPhotoGallery.swift）另一個
//     全螢幕單張檢視器 PhotoLightbox 已有的「載入完成後 easeOut(0.28) 淡入」規格
//     不一致，快速左右滑動翻頁時尤其明顯是生硬的一次性跳出。改為 img 由 nil→有值時
//     以 .transition(.opacity) + .animation(.easeOut(duration: 0.28), value:) 淡入，
//     時間常數直接對齊 PhotoLightbox.imageAppeared，讓 App 內兩個全螢幕照片檢視器
//     載圖手感一致。純視覺調整，未動任何照片讀取／快取邏輯。
//
// [2026-07 v4] 底部資訊面板進場動畫：
//   • RenovationStackViewer 底部標題／頁碼／備註／日期資訊面板原本一開啟就直接
//     定位顯示，全 App 其餘英雄卡（TravelMapView.statsCard／MedicalMapView.summaryCard
//     等）皆已有 opacity 0→1 + 上移 20pt 的 spring(0.55/0.78) 進場動畫，此面板是同類
//     元件中唯一還沒補上的。新增 infoPanelAppeared 旗標，onAppear 觸發、onDisappear
//     歸零（避免分頁切換或重新開啟時動畫不重播）。純視覺調整，未動任何商業邏輯。
//   （下次美化本元件時，可考慮 ExpensePhotoStackViewer 是本元件在 RealEstateDetailView.swift
//     的姊妹版本，目前規格明顯落後──缺大圖淡入、頁碼還是純文字非膠囊、無日期圖示前綴、
//     空狀態仍是純文字、底部面板也無進場動畫，可整批對齊本元件已有的規格。）

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
    // 防止「儲存」連點：save() 把實際寫回 store 的動作延後到下個 runloop（見 save() 內註解），
    // 快速連點兩下會讓兩次呼叫都讀到同一份 estate 快照、各自 append 自己的 RenovationPhoto，
    // 後寫入者會蓋掉前者剛存好的紀錄，其照片檔案則變成永久孤兒。
    @State private var isSaving: Bool = false

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
                        .disabled(photoFileNames.isEmpty || isSaving)
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
        guard !isSaving else { return }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        isSaving = true
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
        // 使用者若在編輯既有紀錄時刪除了「原本已存在」的照片，MultiPhotoGallery 的刪除按鈕
        // 會立即刪檔並同步 CloudKit（不等按下「儲存」），取消時若不回寫 store，紀錄仍會留著
        // 已被刪除照片的檔名，變成永久指向不存在檔案的孤兒引用（縮圖破圖／無限載入中）。
        let remaining = photoFileNames.filter { original.contains($0) }
        if let e = editing, Set(remaining) != original,
           var estate = store.realEstates.first(where: { $0.id == estateId }),
           let idx = estate.renovationPhotos.firstIndex(where: { $0.id == e.id }) {
            estate.renovationPhotos[idx].photoFileNames = remaining
            let financeStore = store
            dismiss()
            DispatchQueue.main.async { financeStore.update(estate) }
            return
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
    // [v4] 底部資訊面板進場動畫旗標，對齊 TravelMapView.statsCardAppeared 等
    // 全 App 英雄卡進場動畫規格（spring 0.55/0.78 + opacity/offset）。
    @State private var infoPanelAppeared = false

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
                                            .transition(.opacity)
                                    } else {
                                        ProgressView().tint(.white)
                                    }
                                }
                                // [v3] 對齊 PhotoLightbox.imageAppeared 淡入時間常數，
                                // 讀圖完成瞬間由 nil→有值時平滑淡入，取代原本的生硬硬切。
                                .animation(.easeOut(duration: 0.28), value: img != nil)
                            }
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }

                VStack {
                    Spacer()
                    // 目前這張的照片資訊：檔名 / 解析度 / 檔案大小（與 PhotoLightbox 共用 PhotoInfoBar）
                    if record.photoFileNames.indices.contains(currentIndex) {
                        PhotoInfoBar(url: RenovationPhoto.photoURL(for: record.photoFileNames[currentIndex]))
                            .padding(.bottom, 8)
                    }
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
                        // [v4] 底部資訊面板進場動畫：opacity 0→1 + 上移 20pt，
                        // spring(0.55/0.78) 對齊全 App 英雄卡進場動畫規格，
                        // 取代原本一開啟就直接定位、毫無過場的生硬手感。
                        .opacity(infoPanelAppeared ? 1 : 0)
                        .offset(y: infoPanelAppeared ? 0 : 20)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                infoPanelAppeared = true
                            }
                        }
                        .onDisappear { infoPanelAppeared = false }
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
