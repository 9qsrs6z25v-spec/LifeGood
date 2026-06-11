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

// MARK: - 多照片廊（可拍照 / 從相簿多選 / 點看大圖 / 刪除）

/// 通用的多張照片廊。將檔案以 jpeg 寫入指定資料夾，呼叫 onAdd / onDelete 回傳檔名給呼叫端。
///
/// 呼叫端負責把 fileNames 寫入自己的資料模型；本元件只負責 IO 與 UI。
struct MultiPhotoGallery: View {
    @Binding var fileNames: [String]
    /// 取得單一檔名的本地 URL（呼叫端決定資料夾）
    let urlFor: (String) -> URL
    /// 寫入 jpeg 後回傳檔名（資料夾與命名規則由呼叫端決定）
    let onSaveImage: (Data) -> String
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
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let name = onSaveImage(data)
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
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let name = onSaveImage(data)
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

    // 縮圖：cornerRadius 12 + 雙層陰影 + 白色邊框；載入佔位用 LinearGradient + caption
    @ViewBuilder
    private func thumbnail(for name: String) -> some View {
        let url = urlFor(name)
        ZStack(alignment: .topTrailing) {
            Button {
                viewingURL = IdentifiableURL(url: url)
            } label: {
                Group {
                    if let img = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
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
                            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
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
            }
            .buttonStyle(.plain)
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

// MARK: - 全螢幕燈箱檢視

struct PhotoLightbox: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var image: UIImage?

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

                // 前景：原圖
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
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
            } else {
                ProgressView().tint(.white)
            }

            // 關閉按鈕：Circle + ultraThinMaterial，暗色 / 明色模式皆自適應
            VStack {
                HStack {
                    Spacer()
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
                }
                Spacer()
            }
        }
        .onAppear {
            if image == nil { image = UIImage(contentsOfFile: url.path) }
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
