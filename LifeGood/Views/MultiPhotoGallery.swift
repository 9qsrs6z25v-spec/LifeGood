import SwiftUI
import PhotosUI
import UIKit

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
                    HStack(spacing: 8) {
                        ForEach(fileNames, id: \.self) { name in
                            thumbnail(for: name)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.85), let name = onSaveImage(data) {
                    fileNames.append(name)
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
            Task {
                var added: [String] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let name = onSaveImage(data) {
                        added.append(name)
                    }
                }
                await MainActor.run {
                    fileNames.append(contentsOf: added)
                    pickerItems = []
                }
            }
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
            let path = url.path
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded
        }
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
    }
}

// MARK: - 全螢幕燈箱檢視

struct PhotoLightbox: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
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

                // 前景：原圖
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .opacity(imageAppeared ? 1 : 0)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(5, lastScale * value))
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2; lastScale = scale }
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
