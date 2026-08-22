import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import Combine

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

    /// 顯示標題（例：「照片」「裝潢照片」）
    var title: String = "照片"
    /// 是否允許新增
    var allowAdding: Bool = true
    /// 縮圖大小
    var thumbnailSize: CGSize = CGSize(width: 110, height: 90)

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var showPhotosPicker: Bool = false
    @State private var viewingURL: IdentifiableURL?
    @State private var pendingDeleteName: String?
    @State private var photoLoadTask: Task<Void, Never>?

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
                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("從相簿多選", systemImage: "photo.on.rectangle.angled")
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
            photoLoadTask?.cancel()
            // 用 Task.detached：原本裸 Task 會沿用 onChange 所在的 MainActor context，
            // 每張照片的 onSaveImage（savePhoto → ImageCompressor 壓縮 → 磁碟寫入）
            // 其實仍在主執行緒逐張跑完才輪到下一張，多選張數一多就會卡住畫面；
            // 改成真正的背景執行緒，只在最後 append 時才回主執行緒。
            photoLoadTask = Task.detached(priority: .userInitiated) {
                var added: [String] = []
                for item in items {
                    guard !Task.isCancelled else { break }
                    if let data = try? await item.loadTransferable(type: Data.self), let name = onSaveImage(data) {
                        added.append(name)
                    }
                }
                guard !Task.isCancelled else {
                    added.forEach(onDeleteFile)
                    return
                }
                await MainActor.run {
                    fileNames.append(contentsOf: added)
                    pickerItems = []
                }
            }
        }
        .onDisappear {
            photoLoadTask?.cancel()
        }
        .sheet(item: $viewingURL) { wrapper in
            PhotoLightbox(url: wrapper.url)
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
            Text("尚無照片，按右上角 ＋ 拍照或從相簿選取")
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
        ZStack(alignment: .topTrailing) {
            Button {
                viewingURL = IdentifiableURL(url: url)
            } label: {
                AsyncThumbnailView(url: url, size: thumbnailSize)
            }
            .buttonStyle(PressableScaleStyle())
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

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

struct PhotoLightbox: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var image: UIImage?
    @State private var imageAppeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = image {
                // 背景：同一張照片放大填滿 + 高斯模糊 + 輕微暗化，讓畫面不再死黑
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .opacity(imageAppeared ? 1 : 0)
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
                                    guard scale > 1 else { return }   // fit 狀態不平移
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
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
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.30), radius: 6, x: 0, y: 3)
                            )
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
                // 照片資訊列：檔名 / 解析度 / 檔案大小
                PhotoInfoBar(url: url, image: image)
                    .padding(.bottom, 18)
            }
        }
        .task(id: url) {
            // 重置為載入中狀態：.task(id: url) 只在 url 改變時重新觸發，但先前用
            // `image == nil` 當作「是否已讀過」的判斷在 url 改變、image 已非 nil
            // （上一張圖已快取）時會誤判為已載入而直接 return，導致换照片後畫面
            // 停留在舊圖；改成每次 url 改變都清空重讀。
            image = nil
            let path = url.path
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded
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
