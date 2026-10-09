import SwiftUI
import PhotosUI
// [v25.471] 存進相簿要用 PHPhotoLibrary／PHAssetChangeRequest。
// PhotosUI 是否轉出 Photos 不保證，明著 import 免得日後換 SDK 才爆。
import Photos
import UIKit
import ImageIO
import Combine
import PDFKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - 美化紀錄（v1 · 2026-06-11）
// • Header：標題升級 .bold、數量改為綠色 Capsule 膠囊徽章（fill opacity 0.13），
//   與全 App section header count badge 風格一致；新增按鈕加綠色光暈陰影
// • emptyState：純文字升級為「36pt 漸層圓 + strokeBorder + 圖示 + 提示文字」橫排版型，
//   漸層方向 topLeading→bottomTrailing，綠色 opacity 0.22→0.09，
//   對齊全 App inline 空狀態（LifeOverview / CareerView 等同款）
// • thumbnail：cornerRadius 10→12，雙層陰影（black 0.10 r6 + black 0.04 r2），
//   白色邊框 strokeBorder opacity 0.20 overlay；載入佔位改用 LinearGradient 填滿＋「載入中」caption；
//   xmark 刪除按鈕加 shadow 提升暗背景可見度
// • PhotoLightbox 關閉按鈕：改用 36pt Circle + .ultraThinMaterial 背景＋陰影，
//   視覺層次清晰，暗色 / 明色模式皆自適應
//
// [2026-07 v2] 一致性 + 動畫小步美化：
// • PhotoLightbox 關閉按鈕：右上角 → 左上角，對齊全 App 慣例
//   （ChildDetailView / DailyRecordEditorSheet / ChildRecordEditorSheet 等
//   均以 ToolbarItem(.topBarLeading) 放置「關閉／取消」）
//   [2026-07 修正] 當時誤判為「唯一例外」：AddRealEstateView.PhotoViewerSheet
//   （全 App 共用照片檢視器）也曾把「關閉」放在 topBarTrailing，已於該檔案同步修正，
//   詳見 AddRealEstateView.swift 內 PhotoViewerSheet 美化紀錄。
// • PhotoLightbox 圖片載入：背景模糊層 + 前景大圖改為載入完成後淡入（0.28s ease），
//   取代原本從 ProgressView 直接跳成圖片的生硬切換
// • 縮圖 thumbnail：按下時加入輕量 scaleEffect(0.96) 回饋，提升點擊可感知性
//   （下次美化本元件時，可從這裡接著找其他可統一之處）

// MARK: - 多照片廊（可拍照 / 從相簿多選 / 點看大圖 / 刪除）

/// 通用的多張照片廊。將檔案以 jpeg 寫入指定資料夾，呼叫 onAdd / onDelete 回傳檔名給呼叫端。
///
/// 呼叫端負責把 fileNames 寫入自己的資料模型；本元件只負責 IO 與 UI。
struct MultiPhotoGallery: View {
    @Binding var fileNames: [String]
    /// 取得單一檔名的本地 URL（呼叫端決定資料夾）
    let urlFor: (String) -> URL
    /// 寫入 jpeg 後回傳檔名（資料夾與命名規則由呼叫端決定）；寫入失敗回傳 nil
    let onSaveImage: (Data) -> String?
    /// 刪除單一檔名
    let onDeleteFile: (String) -> Void
    /// [v25.306] 寫入 PDF 原檔後回傳檔名；nil＝此畫面不開放選 PDF（例：不支援 PDF 的相片廊）
    var onSavePDF: ((Data) -> String?)? = nil

    /// 顯示標題（例：「照片」「裝潢照片」）
    var title: String = "照片"
    /// 是否允許新增
    var allowAdding: Bool = true
    /// 縮圖大小
    var thumbnailSize: CGSize = CGSize(width: 110, height: 90)
    /// [v25.483] 從相簿多選時，把匯入交給 PhotoImportCenter 在背景跑完，
    /// 跑完之後用這個閉包把檔名寫回去。
    ///
    /// 只有「檔名直接落地到 store」的呼叫端可以傳（例：旅遊景點照片寫回 LifeStore）。
    /// 記帳表單那種「按儲存才落地」的畫面**不要傳**——表單一關就沒有人認領那些檔名，
    /// 寫回去只會變成孤兒檔案，那種情況維持原本「離開畫面就取消並清掉」的行為。
    var onBackgroundCommit: (([String]) -> Void)? = nil
    /// [v25.519] 哪一張是封面（縮圖左下角標「封面」）。nil＝這個畫面沒有封面的概念。
    /// 目前只有旅遊景點卡傳（傳的是這一站實際顯示的那張：指定的、或自動的第一張）。
    var coverName: String? = nil
    /// [v25.519] 長按縮圖「設為封面」。nil＝不提供——其他八個呼叫端都是 nil，外觀與行為不變。
    /// 點縮圖照舊是看大圖，長按才是選單。
    var onSetCover: ((String) -> Void)? = nil

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var showPhotosPicker: Bool = false
    @State private var showPDFImporter: Bool = false
    /// [v25.311] 文件掃描（VisionKit：自動偵測文件邊框、透視校正拉成長方形）
    @State private var showDocScanner: Bool = false
    @State private var viewingURL: IdentifiableURL?
    @State private var pendingDeleteName: String?
    @State private var photoLoadTask: Task<Void, Never>?
    /// [v25.422] 正在載入的進度（已完成張數 / 總張數）。
    /// iCloud 相簿的原圖要先下載，沒有提示的話按了打勾看起來就像沒選到。
    @State private var loadingDone = 0
    @State private var loadingTotal = 0
    /// [v25.483] 背景匯入的進度（這個畫面還開著的時候也要看得到）
    @ObservedObject private var importCenter = PhotoImportCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 標題列：bold 標題 + 數量膠囊徽章 + 新增 Menu 按鈕
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                if !fileNames.isEmpty {
                    Text("\(fileNames.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.13)))
                }
                Spacer()
                if allowAdding {
                    Menu {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                        }
                        // [v25.311] 掃描文件：拍帳單/文件時自動偵測形狀、
                        // 透視校正拉成長方形（與名片掃描同一套系統掃描器，可連拍多頁）
                        if VNDocumentCameraViewController.isSupported {
                            Button {
                                showDocScanner = true
                            } label: {
                                Label("掃描文件（自動裁切）", systemImage: "doc.viewfinder")
                            }
                        }
                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("從相簿多選", systemImage: "photo.on.rectangle.angled")
                        }
                        // [v25.306] PDF 帳單：從檔案 App 選 PDF 原檔（可多選）
                        if onSavePDF != nil {
                            Button {
                                showPDFImporter = true
                            } label: {
                                Label("選取 PDF 檔案", systemImage: "doc.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                            .shadow(color: Color.green.opacity(0.30), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, 4)

            // [v25.422] 載入中的提示。從 iCloud 相簿選的照片要先把原圖下載回來，
            // 這段期間畫面上原本什麼都不會變，使用者只會覺得「我剛剛是不是沒選到」。
            if loadingTotal > 0 {
                ThinProgressBar(
                    label: loadingDone >= loadingTotal
                        ? "正在存入…"
                        : "正在取得照片 \(loadingDone + 1) / \(loadingTotal)（iCloud 的原圖要先下載）",
                    fraction: Double(loadingDone) / Double(max(1, loadingTotal)))
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            } else if onBackgroundCommit != nil && importCenter.isImporting {
                // [v25.483] 背景匯入：這裡照樣看得到，但關掉畫面也不會中斷，
                // 所以要明講「可以先離開」——不然使用者還是會乖乖在這裡等。
                ThinProgressBar(
                    label: importCenter.statusText + "（可以先離開這個畫面）",
                    fraction: importCenter.fraction)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            if fileNames.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    // LazyHStack：相片數量多時（20-30+ 張收據／裝潢照）避免一次把所有縮圖
                    // 都實例化並觸發磁碟讀取＋JPEG 解碼，只在捲動到可視範圍附近才載入。
                    LazyHStack(spacing: 8) {
                        ForEach(fileNames, id: \.self) { name in
                            thumbnail(for: name)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        // 連拍相機改用 .fullScreenCover：先前用 .sheet 在 iPhone 上是「卡片式」呈現，
        // 實際可視高度比整個螢幕矮一截，但 overlay 以全螢幕高度排版，快門/完成鈕
        // 底部超出卡片可視範圍被切掉一半（使用者截圖回報）。相機介面本應全螢幕。
        .fullScreenCover(isPresented: $showCamera) {
            // 連拍相機：拍一張存一張（onSaveImage → 各模型 savePhoto → ImageCompressor 壓縮
            // → PhotoCloudSync 上傳），按「完成」才離開，可一次連拍多張收據/照片。
            // JPEG 編碼＋ImageCompressor 二次解碼壓縮＋磁碟寫入原本直接同步跑在
            // UIImagePickerController delegate 回呼所在的主執行緒，每拍一張就卡住
            // 即時預覽與快門回應；改用背景執行緒處理，只在寫入完成後才回主執行緒
            // 更新 fileNames。
            MultiShotCameraPicker { image in
                Task.detached(priority: .userInitiated) {
                    guard let data = image.jpegData(compressionQuality: 0.85),
                          let name = onSaveImage(data) else { return }
                    await MainActor.run {
                        fileNames.append(name)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotosPicker,
                      selection: $pickerItems,
                      maxSelectionCount: 0,
                      matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            // 原本是無主的裸 Task，不隨畫面關閉自動取消：多選張數多、iCloud 原圖需下載時，
            // 使用者若在載入完成前就關閉表單（取消／儲存），Task 仍會在背景繼續把照片寫入磁碟，
            // 但寫完後 append 的對象已是脫離畫面的 fileNames，資料從未被任何紀錄引用到，
            // 變成永久孤兒檔案。改用可取消的 Task：畫面消失時取消，且取消時把這批已寫入磁碟
            // 但還沒機會被採用的照片一併刪除。
            // [v25.483] 有 commit 閉包的呼叫端：交給匯入中心，離開畫面也會跑完
            if let commit = onBackgroundCommit {
                PhotoImportCenter.shared.enqueue(items: items, label: title,
                                                 save: onSaveImage, commit: commit)
                pickerItems = []
                return
            }
            photoLoadTask?.cancel()
            loadingDone = 0
            loadingTotal = items.count
            // 用 Task.detached：原本裸 Task 會沿用 onChange 所在的 MainActor context，
            // 每張照片的 onSaveImage（savePhoto → ImageCompressor 壓縮 → 磁碟寫入）
            // 其實仍在主執行緒逐張跑完才輪到下一張，多選張數一多就會卡住畫面；
            // 改成真正的背景執行緒，只在最後 append 時才回主執行緒。
            photoLoadTask = Task.detached(priority: .userInitiated) {
                var added: [String] = []
                for item in items {
                    guard !Task.isCancelled else { break }
                    // 這一行就是會卡住的地方：照片只存在 iCloud 時要先整張下載回來
                    if let data = try? await item.loadTransferable(type: Data.self), let name = onSaveImage(data) {
                        added.append(name)
                    }
                    await MainActor.run { loadingDone += 1 }
                }
                guard !Task.isCancelled else {
                    added.forEach(onDeleteFile)
                    await MainActor.run { loadingTotal = 0; loadingDone = 0 }
                    return
                }
                await MainActor.run {
                    fileNames.append(contentsOf: added)
                    pickerItems = []
                    loadingTotal = 0
                    loadingDone = 0
                }
            }
        }
        .onDisappear {
            photoLoadTask?.cancel()
            loadingTotal = 0
            loadingDone = 0
        }
        // [v25.311] 文件掃描：系統掃描器自動偵測邊框＋透視校正，可一次掃多頁；
        // 拍完逐頁存檔（JPEG 編碼與寫入走背景，比照相簿多選的做法）
        .fullScreenCover(isPresented: $showDocScanner) {
            BusinessCardScannerView(onCapture: { images in
                showDocScanner = false
                Task.detached(priority: .userInitiated) {
                    var added: [String] = []
                    for img in images {
                        guard let data = img.jpegData(compressionQuality: 0.85),
                              let name = onSaveImage(data) else { continue }
                        added.append(name)
                    }
                    let names = added
                    await MainActor.run { fileNames.append(contentsOf: names) }
                }
            }, onCancel: {
                showDocScanner = false
            })
            .ignoresSafeArea()
        }
        // [v25.306] 選取 PDF：security-scoped 讀取原檔資料後交給呼叫端寫入
        .fileImporter(isPresented: $showPDFImporter,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, let save = onSavePDF else { return }
            var added: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), let name = save(data) else { continue }
                added.append(name)
            }
            fileNames.append(contentsOf: added)
        }
        .sheet(item: $viewingURL) { wrapper in
            // PDF 走 PDFKit 檢視器（可捲頁、雙指縮放）；圖片維持原本的燈箱
            if wrapper.url.pathExtension.lowercased() == "pdf" {
                PDFLightbox(url: wrapper.url)
            } else {
                // [v25.472] 同一組照片一起帶進去（PDF 排除——燈箱不收 PDF）
                PhotoLightbox(urls: fileNames.map(urlFor)
                                .filter { $0.pathExtension.lowercased() != "pdf" },
                              current: wrapper.url)
            }
        }
        .alert("移除這張照片？", isPresented: Binding(
            get: { pendingDeleteName != nil },
            set: { if !$0 { pendingDeleteName = nil } }
        )) {
            Button("移除", role: .destructive) {
                if let name = pendingDeleteName {
                    onDeleteFile(name)
                    fileNames.removeAll { $0 == name }
                }
                pendingDeleteName = nil
            }
            Button("取消", role: .cancel) { pendingDeleteName = nil }
        }
    }

    /// [v25.519] 縮圖左下的「封面」小標
    private static var coverTag: some View {
        Text("封面")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.black.opacity(0.6), in: Capsule())
            .padding(5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // 空狀態：36pt 漸層圓（topLeading→bottomTrailing 0.22→0.09）+ strokeBorder + 圖示 + 提示文字
    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.22), Color.green.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.70))
            }
            Text(onSavePDF != nil
                 ? "尚無檔案，按右上角 ＋ 拍照、選相簿照片或 PDF 帳單"
                 : "尚無照片，按右上角 ＋ 拍照或從相簿選取")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    // 縮圖：cornerRadius 12 + 雙層陰影 + 白色邊框；非同步載入避免在 view body 阻塞主執行緒
    @ViewBuilder
    private func thumbnail(for name: String) -> some View {
        let url = urlFor(name)
        let isPDF = name.lowercased().hasSuffix(".pdf")
        let isCover = !isPDF && coverName == name
        // 字串先組好（規矩：三元不直接塞進 Text／Label）
        let coverValue: String = isCover ? "封面" : ""
        let coverMenuTitle: String = isCover ? "這張是封面" : "設為封面"
        let coverMenuIcon: String = isCover ? "checkmark.circle" : "rectangle.portrait.inset.filled"
        ZStack(alignment: .topTrailing) {
            let face = Button {
                viewingURL = IdentifiableURL(url: url)
            } label: {
                if isPDF {
                    PDFThumbView(url: url, size: thumbnailSize)
                } else {
                    AsyncThumbnailView(url: url, size: thumbnailSize)
                }
            }
            .buttonStyle(PressableScaleStyle())
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            // [v25.519] 封面那張左下角一個小標（右上角是刪除的 ×，不搶位置）
            .overlay(alignment: .bottomLeading) {
                if isCover { Self.coverTag }
            }
            .accessibilityValue(coverValue)

            if let onSetCover, !isPDF {
                face
                    .contextMenu {
                        Button {
                            onSetCover(name)
                        } label: {
                            Label(coverMenuTitle, systemImage: coverMenuIcon)
                        }
                        .disabled(isCover)
                    }
                    .accessibilityAction(named: "設為封面") { onSetCover(name) }
            } else {
                face
            }

            if allowAdding {
                Button {
                    pendingDeleteName = name
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.60))
                        .shadow(color: .black.opacity(0.30), radius: 3, x: 0, y: 1)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - PDF 縮圖與檢視（v25.306：帳單支援 PDF 原檔）

/// PDF 縮圖：背景渲染第 1 頁當縮圖，左下角帶紅色「PDF」徽章。
/// 渲染走 detached task，不在 view body 阻塞主執行緒（比照 AsyncThumbnailView）。
struct PDFThumbView: View {
    let url: URL
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(.systemGray5), Color(.systemGray6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "doc.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1))

            Text("PDF")
                .font(.system(size: 9, weight: .heavy))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
                .padding(5)
        }
        .task(id: url) {
            guard image == nil else { return }
            let target = CGSize(width: size.width * 2, height: size.height * 2)
            let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
                return page.thumbnail(of: target, for: .mediaBox)
            }.value
            image = rendered
        }
    }
}

/// PDF 檢視器：PDFKit 全文檢視（可捲頁、雙指縮放），左上關閉、右上分享原檔。
struct PDFLightbox: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("PDF 帳單")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }
}

/// PDFView 的 SwiftUI 包裝（autoScales 打開＝開檔即整頁貼合）
private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - 輕量按下回饋（縮圖點擊用）

/// 縮放至 0.96 + 0.12s ease-out，讓點擊縮圖時有明確的觸控回饋
private struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 非同步縮圖載入（避免在 view body 同步讀檔阻塞主執行緒）
// [2026-07 v3] 拿掉 private，讓其他畫面的照片縮圖列（例如 MedicalMapView.photoRow）
// 可共用同一套非同步載入 + 載入中佔位樣式，取代各自手刻的 UIImage(contentsOfFile:)
// 同步讀檔（詳見 MedicalMapView.swift 內對應美化紀錄）。

struct AsyncThumbnailView: View {
    let url: URL
    let size: CGSize
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(.tertiarySystemFill), Color(.secondarySystemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Text("載入中")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    )
            }
        }
        .task(id: url) {
            // 重置為載入中狀態：.task(id: url) 只在 url 改變時重新觸發，但先前用
            // `image == nil` 當作「是否已讀過」的判斷在 url 改變、image 已非 nil
            // （上一張圖已快取）時會誤判為已載入而直接 return，導致换照片後畫面
            // 停留在舊圖；改成每次 url 改變都清空重讀。
            image = nil
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: thumbnailMaxPixel)
        }
        // CloudSyncManager 拉到照片變更時發送 cloudSyncPhotosDidUpdate：若本畫面此刻仍停在
        // 「載入中」佔位（image 為 nil，代表 .task(id: url) 觸發時檔案尚未同步到本機），
        // url 本身不會改變、.task(id:) 也就不會重跑，畫面會卡在佔位圖直到使用者離開再進入
        // 這個 View 實例。收到通知時補一次重讀，讓已落地的照片不必等重新整個畫面才顯示。
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
            guard image == nil else { return }
            Task {
                let loaded = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: thumbnailMaxPixel)
                if loaded != nil { image = loaded }
            }
        }
    }

    // 縮圖只會以 size（點）大小顯示，用 ImageIO 降採樣到「顯示尺寸 × 螢幕縮放係數」即可，
    // 不必解碼 ImageCompressor 儲存的原始全解析度（最長邊可達 1920px）大圖，減少記憶體與 CPU。
    private var thumbnailMaxPixel: CGFloat {
        max(size.width, size.height) * UIScreen.main.scale
    }
}

// MARK: - 非同步讀檔（供各畫面自訂佔位樣式時共用）
// [2026-07] 供 TabView 逐張瀏覽等需要自訂「載入中／找不到照片」樣式的畫面共用，
// 統一 UIImage(contentsOfFile:) 背景執行緒讀檔手法，避免在 view body 同步讀檔阻塞主執行緒。
// didLoad 為 true 且 image 為 nil 時代表確定讀不到檔案（非仍在載入中），呼叫端可據此
// 分辨「載入中」與「找不到照片」兩種狀態，避免載入中誤閃一次「找不到照片」畫面。

struct AsyncLocalImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (_ image: UIImage?, _ didLoad: Bool) -> Content
    @State private var image: UIImage?
    @State private var didLoad = false

    var body: some View {
        content(image, didLoad)
            .task(id: url) {
                // 重置為載入中狀態：.task(id: url) 只在 url 改變時重新觸發，但先前用
                // `!didLoad` 這個「是否已讀過」的一次性旗標判斷，在同一個 view 實例
                // 換了 url（例如同一張名片／頭像換照片但檔名不同）時仍為 true，會誤判
                // 已載入而直接 return，導致换照片後畫面停留在舊圖；改成每次 url 改變
                // 都清空重讀。
                image = nil
                didLoad = false
                let path = url.path
                let loaded = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: path)
                }.value
                image = loaded
                didLoad = true
            }
            // 同 AsyncThumbnailView：url 不變時 .task(id:) 不會因照片位元組稍後才從
            // iCloud 落地而重跑，收到 cloudSyncPhotosDidUpdate 時若仍讀不到檔案就補一次重讀。
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPhotosDidUpdate)) { _ in
                guard image == nil else { return }
                let path = url.path
                Task {
                    let loaded = await Task.detached(priority: .userInitiated) {
                        UIImage(contentsOfFile: path)
                    }.value
                    if loaded != nil {
                        image = loaded
                        didLoad = true
                    }
                }
            }
    }
}

// MARK: - 全螢幕燈箱檢視

/// [v25.477] 大圖的記憶體快取（只給全螢幕檢視用）。
///
/// 為什麼不直接用既有的 ThumbnailCache：那一份是「降採樣的小縮圖、非同步讀」，
/// 給相簿格子用的；這裡要的是**原解析度**（放大到 5 倍還要清楚）而且必須
/// **同步讀得到**——左右滑到下一張時，如果還要等一個 await 才拿得到圖，
/// 畫面就會先閃一下黑底再出現，那正是使用者說的割裂感。
///
/// 兩個細節：
///   • 存進來之前先 preparingForDisplay()：UIImage(contentsOfFile:) 是延遲解碼的，
///     真正的解碼會發生在第一次上畫面時、而且在主執行緒上。只放進快取不預先解碼
///     的話，照片是「載好了」但滑過去還是會掉幀。
///   • 數量壓得很低（原圖 1024×1536 解開就是 6MB，12MP 的照片是 48MB）。
///     NSCache 本來就會在記憶體吃緊時自己清掉，這裡再加一層上限當保險。
final class FullImageCache {
    static let shared = FullImageCache()
    private let cache = NSCache<NSString, UIImage>()
    /// 正在預抓的，避免同一張被排好幾次。
    /// 單例，所以背景工作直接回頭取 shared，不繞 weak self——
    /// 那會變成「鎖與解鎖各自可能沒發生」的寫法。
    fileprivate let lock = NSLock()
    fileprivate var inFlight: Set<String> = []

    private init() {
        cache.countLimit = 8
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height
                       * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url.path as NSString, cost: cost)
    }

    /// 讀一張（已經在快取裡就直接回）。給「目前這一張」用。
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        let path = url.path
        let decoded = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: path)?.preparingForDisplay()
                ?? UIImage(contentsOfFile: path)
        }.value
        if let decoded { insert(decoded, for: url) }
        return decoded
    }

    /// 背景預抓（左右鄰居）。優先權刻意比目前這張低——
    /// 搶在目前這張前面解碼只會讓使用者等更久。
    func prefetch(_ urls: [URL]) {
        for url in urls {
            guard image(for: url) == nil else { continue }
            let path = url.path
            lock.lock()
            let already = inFlight.contains(path)
            if !already { inFlight.insert(path) }
            lock.unlock()
            guard !already else { continue }
            Task.detached(priority: .utility) {
                let img = UIImage(contentsOfFile: path)?.preparingForDisplay()
                    ?? UIImage(contentsOfFile: path)
                let shared = FullImageCache.shared
                if let img { shared.insert(img, for: URL(fileURLWithPath: path)) }
                shared.lock.lock()
                shared.inFlight.remove(path)
                shared.lock.unlock()
            }
        }
    }
}

struct PhotoLightbox: View {
    /// [v25.472] 整本相簿。單張的呼叫點走 init(url:)，陣列裡就只有一個元素。
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var image: UIImage?
    @State private var imageAppeared = false
    /// [v25.329] 貼合狀態下的下滑關閉：跟手位移，超過門檻放開即關閉
    @State private var dismissDrag: CGFloat = 0
    /// [v25.472] 左右換圖的跟手位移
    @State private var pageDrag: CGFloat = 0
    /// 這一次拖曳被鎖在哪個方向。不鎖的話手指稍微斜一點，
    /// 畫面就會在「換圖」與「下滑關閉」之間來回跳。
    @State private var dragAxis: DragAxis?
    /// [v25.477] 畫面寬度。翻頁動畫要知道「滑出去」是多遠，
    /// 而手勢結束的地方讀不到 GeometryProxy，所以存下來。
    @State private var containerWidth: CGFloat = 0
    /// [v25.477] 翻頁動畫進行中：這段期間不收新的拖曳，不然會一次翻兩張
    @State private var isPaging = false

    private enum DragAxis { case horizontal, vertical }

    /// 單張：維持原本的呼叫方式
    init(url: URL) {
        self.urls = [url]
        _index = State(initialValue: 0)
    }

    /// [v25.472] 相簿：可以左右滑看同一本的其他照片，下方有縮圖列
    init(urls: [URL], current: URL) {
        let list = urls.isEmpty ? [current] : urls
        self.urls = list
        _index = State(initialValue: list.firstIndex(of: current) ?? 0)
    }

    /// 目前這一張。index 永遠夾在範圍內（相簿在背後被刪到剩幾張也不會越界）
    private var url: URL { urls[min(max(index, 0), urls.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = image {
                // 背景：同一張照片放大填滿 + 高斯模糊 + 輕微暗化，讓畫面不再死黑
                // [v25.330] 真正的根因：scaledToFill 的 Image 會把「填滿後的尺寸」回報給父層
                // （橫式名片在直式螢幕填滿高度後寬度約 1440pt），frame(maxWidth: .infinity)
                // 擋不住，整個 ZStack 被撐到比螢幕寬、置中後左右溢出——GeometryReader 因此
                // 拿到超寬容器，前景「貼合」等於貼合到 1440pt 寬（看起來像放超大只剩中間），
                // 左上角關閉鈕也被推到螢幕外（使用者猜得沒錯）。改以 Color.clear 佔位、
                // 圖片放 overlay 再 clipped：Color.clear 只吃父層提案尺寸，不會被圖片撐大。
                Color.clear
                    .overlay(
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
                    .blur(radius: 38, opaque: true)
                    .overlay(Color.black.opacity(0.30))
                    .ignoresSafeArea()
                    .opacity(imageAppeared ? 1 : 0)

                // 前景：原圖。以 GeometryReader 明確計算貼合尺寸——
                // 取「寬度貼齊」與「高度貼齊」兩個縮放比中較小者（v25.289 使用者定義：
                // 寬度 fit 會讓高度出血時就改用高度 fit），保證兩個方向都完整在畫面內。
                // 雙指縮放（可暫時縮小於 fit、放開回彈）、放大後可拖曳平移、雙擊切換。
                GeometryReader { geo in
                    let fitted = Self.fittedSize(img.size, in: geo.size)
                    ZStack {
                        // [v25.477] 拖曳時把左右那一張也畫出來，跟著手指進來。
                        // 只有目前這張在動的話，看起來像「把照片推走、再憑空換一張」；
                        // 看得到下一張跟著進來，才像翻頁。
                        neighbour(index - 1, in: geo, dx: -(geo.size.width + Self.pageGap))
                        Image(uiImage: img)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .scaleEffect(scale)
                            .offset(CGSize(width: offset.width + pageDrag,
                                           height: offset.height + dismissDrag))
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .opacity(imageAppeared ? 1 : 0)
                        neighbour(index + 1, in: geo, dx: geo.size.width + Self.pageGap)
                    }
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // 進行中允許 0.5～8（縮小於 fit 有橡皮筋感），放開再夾回 1～5
                            scale = max(0.5, min(8, lastScale * value))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                scale = max(1, min(5, scale))
                                if scale <= 1 { offset = .zero; lastOffset = .zero }
                            }
                            lastScale = scale
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { v in
                                    // 翻頁動畫還在跑就不要再收手勢（會一次翻兩張）
                                    if isPaging { return }
                                    if scale > 1 {
                                        // 放大狀態：平移
                                        offset = CGSize(width: lastOffset.width + v.translation.width,
                                                        height: lastOffset.height + v.translation.height)
                                        return
                                    }
                                    // [v25.472] 貼合狀態有兩種手勢：左右換圖、下滑關閉。
                                    // 第一次動超過 12pt 就把方向鎖住——不鎖的話手指稍微斜一點，
                                    // 畫面會在兩者之間來回跳。
                                    if dragAxis == nil {
                                        let t = v.translation
                                        if max(abs(t.width), abs(t.height)) > 12 {
                                            dragAxis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                                        }
                                    }
                                    switch dragAxis {
                                    case .horizontal:
                                        // 已經是第一張還往右拉（或最後一張往左拉）就給阻尼，
                                        // 讓「沒有下一張」這件事用手感說出來
                                        let raw = v.translation.width
                                        let atEdge = (raw > 0 && index == 0)
                                            || (raw < 0 && index >= urls.count - 1)
                                        pageDrag = atEdge ? raw * 0.25 : raw
                                    case .vertical:
                                        // [v25.329] 下滑跟手（照片檢視慣例的關閉手勢）
                                        dismissDrag = max(0, v.translation.height)
                                    case nil:
                                        break
                                    }
                                }
                                .onEnded { v in
                                    if scale > 1 {
                                        lastOffset = offset
                                        return
                                    }
                                    switch dragAxis {
                                    case .horizontal:
                                        if pageDrag < -70, index < urls.count - 1 {
                                            page(by: 1)
                                        } else if pageDrag > 70, index > 0 {
                                            page(by: -1)
                                        } else {
                                            withAnimation(.spring(response: 0.32,
                                                                  dampingFraction: 0.85)) {
                                                pageDrag = 0
                                            }
                                        }
                                    case .vertical:
                                        if dismissDrag > 110 {
                                            dismiss()
                                        } else {
                                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                                dismissDrag = 0
                                            }
                                        }
                                    case nil:
                                        break
                                    }
                                    dragAxis = nil
                                }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        if scale > 1 {
                            scale = 1; offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                        lastScale = scale
                    }
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.28)) { imageAppeared = true }
                }
            } else {
                ProgressView().tint(.white)
            }

            // 關閉按鈕：左上角，對齊全 App「關閉／取消」統一放在左側的慣例
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        // [v25.329] 改高對比深色底：名片等大面積白底照片上，
                        // 原本的半透明淺色材質圓鈕會整顆隱形（使用者回報找不到關閉）
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .padding()
                    Spacer()
                    // [v25.472] 第幾張／共幾張。相簿裡滑了幾下之後，
                    // 沒有這個數字就不知道自己在哪裡、還有沒有下一張。
                    if urls.count > 1 {
                        Text("\(index + 1) / \(urls.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        Spacer()
                    }
                    // [v25.471] 存到相簿／分享：關閉鈕的對角（使用者指定的位置）
                    PhotoActionButtons(url: url)
                        .padding()
                }
                Spacer()
                // 照片資訊列：檔名 / 解析度 / 檔案大小
                PhotoInfoBar(url: url, image: image)
                // [v25.472] 相簿縮圖列（比照系統相簿）。只有一張就不擺。
                if urls.count > 1 {
                    filmStrip.padding(.top, 6)
                }
            }
            .padding(.bottom, 14)
        }
        .task(id: url) {
            // [v25.477] 已經預抓到手邊的就直接換上去，不要先清空再讀——
            // 清空會讓畫面閃一下黑底，而這一張明明就在記憶體裡。
            if let cached = FullImageCache.shared.image(for: url) {
                image = cached
                // 直接顯示，不重跑淡入：手指才剛把它滑進畫面，再淡一次會像閃爍
                imageAppeared = true
            } else {
                // 沒快取就照舊：先清空（不清的話會停在上一張），背景解碼後淡入
                image = nil
                image = await FullImageCache.shared.load(url)
            }
            prefetchNeighbours()
        }
    }

    /// [v25.472] 底部縮圖列（系統相簿那條）。點一張直接跳過去。
    private var filmStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                go(to: i)
                            }
                        } label: {
                            AsyncThumbnailView(url: u, size: CGSize(width: 46, height: 46))
                                .frame(width: 46, height: 46)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white, lineWidth: i == index ? 2 : 0)
                                )
                                .opacity(i == index ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 54)
            // 用滑的換圖時，縮圖列要跟著捲——不跟的話滑幾張之後
            // 目前這張就跑到看不見的地方，那條列就沒有意義了
            .onChange(of: index) { _, new in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(index, anchor: .center) }
        }
    }

    /// 兩張之間留的縫，跟系統相簿一樣不要黏在一起
    private static let pageGap: CGFloat = 24

    /// [v25.477] 拖曳中露出的左右鄰居。
    ///
    /// 只在「貼合狀態、而且正在左右拖」時出現，而且**只讀快取、不觸發載入**：
    /// 還沒預抓到的就不畫，維持原本的黑底——總比在拖曳當下塞一個同步解碼進來，
    /// 讓整個手勢卡住要好。
    @ViewBuilder
    private func neighbour(_ i: Int, in geo: GeometryProxy, dx: CGFloat) -> some View {
        if scale <= 1, pageDrag != 0, urls.indices.contains(i),
           let img = FullImageCache.shared.image(for: urls[i]) {
            let fitted = Self.fittedSize(img.size, in: geo.size)
            Image(uiImage: img)
                .resizable()
                .frame(width: fitted.width, height: fitted.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .offset(x: dx + pageDrag)
        }
    }

    /// [v25.477] 翻一頁：先讓目前這張滑出去、鄰居滑進來，**動畫跑完才換 index**。
    ///
    /// 不能先換 index 再把位移收回 0：換的那一刻，原本停在右邊一個畫面寬的
    /// 下一張會瞬間跳到手指那個位置，再從那裡滑回來——方向還是反的
    /// （往左滑卻看到新照片從左邊進來）。等動畫跑完才換就沒有這個問題：
    /// 那一刻鄰居剛好停在「換完之後它該在的位置」，畫面一格都不會動。
    private func page(by step: Int) {
        guard !isPaging else { return }
        let target = index + step
        guard urls.indices.contains(target) else { return }
        isPaging = true
        let distance = max(containerWidth, 1) + Self.pageGap
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            pageDrag = step > 0 ? -distance : distance
        } completion: {
            go(to: target)
            pageDrag = 0
            isPaging = false
        }
    }

    /// [v25.477] 先把左右各兩張解好放著。
    ///
    /// 兩張而不是一張：使用者連滑的時候，手指離開前下一張就該準備好了。
    /// 順序是「先右一、再左一，然後右二、左二」——往前翻比往回翻常見。
    private func prefetchNeighbours() {
        let around = [index + 1, index - 1, index + 2, index - 2]
            .filter { urls.indices.contains($0) }
            .map { urls[$0] }
        FullImageCache.shared.prefetch(around)
    }

    /// 換到第 n 張：縮放與平移一起歸零，不然上一張放大的狀態會跟著帶過去
    private func go(to newIndex: Int) {
        guard urls.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        // [v25.477] 已經在手邊的就當場換上去，並且**不要**重設 imageAppeared：
        // .task 是下一輪才跑的，中間那一幀會是透明的——使用者看到的就是
        // 「滑完先閃一下黑再出現」。沒快取的才回到淡入流程。
        if let cached = FullImageCache.shared.image(for: urls[newIndex]) {
            image = cached
            imageAppeared = true
        } else {
            imageAppeared = false
        }
    }

    /// 貼合尺寸：取寬、高兩個方向縮放比的較小者——寬度 fit 會讓高度出血時
    /// 自動改用高度 fit，兩個方向都不出血
    static func fittedSize(_ imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return container }
        let ratio = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }
}

// MARK: - 照片資訊列（檔名 / 解析度 / 檔案大小）

/// 點開大圖時顯示的照片資訊列，PhotoLightbox／PhotoViewerSheet 共用。
/// 檔案大小以 .task 於背景讀取（避免主執行緒磁碟 IO）；解析度取自已解碼影像的像素尺寸。
struct PhotoInfoBar: View {
    let url: URL
    /// 已載入的影像（由呼叫端傳入，避免重複解碼）；nil 時改由 ImageIO 讀取中繼資料取得解析度
    var image: UIImage? = nil

    @State private var fileSizeText: String = "…"
    @State private var loadedResolution: String?

    private var resolutionText: String {
        if let img = image {
            let w = Int(img.size.width * img.scale)
            let h = Int(img.size.height * img.scale)
            return "\(w) × \(h)"
        }
        return loadedResolution ?? "…"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(url.lastPathComponent)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 12) {
                Label(resolutionText, systemImage: "aspectratio")
                Label(fileSizeText, systemImage: "internaldrive")
            }
            .font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        .task(id: url) {
            fileSizeText = "…"
            loadedResolution = nil
            let path = url.path
            let needResolution = (image == nil)
            let info = await Task.detached(priority: .utility) { () -> (bytes: Int, resolution: String?) in
                let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
                var resolution: String?
                if needResolution,
                   let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? Int,
                   let h = props[kCGImagePropertyPixelHeight] as? Int {
                    resolution = "\(w) × \(h)"
                }
                return (bytes, resolution)
            }.value
            if info.bytes >= 1_048_576 {
                fileSizeText = String(format: "%.1f MB", Double(info.bytes) / 1_048_576)
            } else if info.bytes > 0 {
                fileSizeText = String(format: "%.0f KB", Double(info.bytes) / 1024)
            } else {
                fileSizeText = "—"
            }
            loadedResolution = info.resolution
        }
    }
}

// MARK: - URL Identifiable wrapper（給 .sheet(item:) 用）

struct IdentifiableURL: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

// MARK: - 通用：可縮放圖片（UIScrollView wrap）

/// 用 UIScrollView 包圖片提供原生雙指縮放 + 拖曳 + 雙擊縮放/還原。
/// 給 stack viewer（裝潢照片 / 支出照片）共用。
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var maxZoom: CGFloat = 5.0

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            uiView.setZoomScale(1.0, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // 縮放時把圖片置中
            guard let iv = imageView else { return }
            let bound = scrollView.bounds.size
            let content = iv.frame.size
            let offX = max(0, (bound.width - content.width) / 2)
            let offY = max(0, (bound.height - content.height) / 2)
            iv.center = CGPoint(
                x: content.width / 2 + offX,
                y: content.height / 2 + offY
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let sv = gesture.view as? UIScrollView else { return }
            if sv.zoomScale > 1.0 {
                sv.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let zoomRect = CGRect(
                    x: point.x - sv.bounds.width / 6,
                    y: point.y - sv.bounds.height / 6,
                    width: sv.bounds.width / 3,
                    height: sv.bounds.height / 3
                )
                sv.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

// MARK: - 大圖預覽的「存到相簿／分享」（v25.471）

/// 放在大圖預覽右上角（關閉鈕的對角）的兩顆按鈕。
///
/// 使用者要求：所有圖片預覽都要能存進相簿或分享出去。做成共用元件而不是在每個
/// 檢視器各寫一份——App 裡有四個預覽（PhotoLightbox／CutePhotoViewer／
/// PhotoViewerSheet／PDFLightbox），各寫一份就是四份會各自長歪的權限處理。
///
/// 存檔走 PHAssetChangeRequest(forAssetFromImageAtFileURL:) 而不是
/// UIImageWriteToSavedPhotosAlbum：後者吃的是 UIImage，等於把原檔重新編碼一次
/// （畫質損失、EXIF 也掉了）；前者是把原始檔案整個放進相簿。
struct PhotoActionButtons: View {
    let url: URL
    /// 只有分享用得到的備用項目；nil 就分享檔案本身
    var shareItems: [Any]?
    /// 這個檔案存不存得進相簿（PDF 不行，只能分享）
    var canSaveToPhotos: Bool = true
    /// 掛在導覽列工具列上時不要自己的深色圓底——工具列已經有它自己的外框，
    /// 再疊一層會變成一顆突兀的黑球。
    var chromeless: Bool = false

    @State private var saveState: SaveState = .idle
    @State private var showShare = false
    @State private var errorMessage: String?

    enum SaveState { case idle, saving, saved }

    var body: some View {
        HStack(spacing: 10) {
            if canSaveToPhotos { saveButton }
            shareButton
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems ?? [url])
        }
        .alert("存不進相簿", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            circle(icon: saveState == .saved ? "checkmark" : "arrow.down.to.line",
                   tint: saveState == .saved ? .green : .white,
                   busy: saveState == .saving)
        }
        .disabled(saveState == .saving)
        .accessibilityLabel("存到相簿")
    }

    private var shareButton: some View {
        Button {
            showShare = true
        } label: {
            circle(icon: "square.and.arrow.up", tint: .white, busy: false)
        }
        .accessibilityLabel("分享")
    }

    /// 與關閉鈕同一套規格：深色底＋白色描邊。
    /// 淺色半透明材質在大面積白底照片（名片、登機證）上會整顆隱形——
    /// v25.329 關閉鈕就是為了這件事改過一次，這兩顆直接沿用結論。
    @ViewBuilder
    private func circle(icon: String, tint: Color, busy: Bool) -> some View {
        let content = ZStack {
            if busy {
                ProgressView().tint(.white).scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        if chromeless {
            content
        } else {
            content
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                )
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }

    private func save() {
        saveState = .saving
        // .addOnly：只要「加入」的權限，不要求讀取整個相簿。
        // 要讀取權限會讓系統問一個使用者根本不需要答應的問題。
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveState = .idle
                    errorMessage = "沒有「加入相簿」的權限。要開啟請到「設定 → LifeGood → 照片」改成「加入照片」或「完整取用權」。"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            } completionHandler: { ok, error in
                DispatchQueue.main.async {
                    if ok {
                        saveState = .saved
                        // 打勾留兩秒就好——一直停在打勾會讓人以為按不了第二次
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if saveState == .saved { saveState = .idle }
                        }
                    } else {
                        saveState = .idle
                        errorMessage = error?.localizedDescription ?? "系統沒有說原因。"
                    }
                }
            }
        }
    }
}
