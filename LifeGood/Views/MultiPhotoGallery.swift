import SwiftUI
import PhotosUI
import UIKit

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
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(fileNames.count) 張")
                    .font(.caption2).foregroundStyle(.tertiary)
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

    @ViewBuilder
    private var emptyState: some View {
        HStack {
            Image(systemName: "photo")
                .foregroundStyle(.tertiary)
            Text("尚無照片，按右上角＋拍照或從相簿選取")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
    }

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
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                            .overlay(
                                Image(systemName: "icloud.and.arrow.down")
                                    .foregroundStyle(.tertiary)
                            )
                    }
                }
            }
            .buttonStyle(.plain)

            if allowAdding {
                Button {
                    pendingDeleteName = name
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.55))
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = UIImage(contentsOfFile: url.path) {
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

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }
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
