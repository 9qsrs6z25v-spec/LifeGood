import SwiftUI

// MARK: - 地圖相簿共用模板
//
// 旅遊地圖／美食地圖／醫療地圖共用的相簿 Sheet。各頁面把照片彙整成
// AlbumPhotoItem（照片 URL＋所屬地點＋日期）傳入，模板負責顯示與互動：
//   • 摘要列：共 N 張照片・M 個地點
//   • 分組切換：依地點 / 依月份 / 全部（時間新到舊）
//   • 格狀縮圖（adaptive 104pt），點開進 PhotoLightbox 全螢幕檢視
//     （含檔名/解析度/檔案大小資訊列）
//   • 空狀態：主題色雙層脈衝光環＋自訂提示文案
// 主題色（accent）、標題與空狀態文案由呼叫端配置，視覺自動跟隨各地圖主題。

/// 相簿中的一張照片：檔案 URL＋所屬地點＋拍攝（消費）日期
struct AlbumPhotoItem: Identifiable {
    let id: String          // photoFileName（穩定、不重複）
    let url: URL
    let group: String       // 地點名稱（依地點分組用）
    let date: Date          // 所屬紀錄日期（依月份分組／排序用）
}

struct MapAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String               // 例：「旅遊相簿」「美食相簿」「醫療相簿」
    let accent: Color               // 各地圖主題色
    let emptyTitle: String          // 例：「還沒有旅遊照片」
    let emptyHint: String           // 例：「在娛樂支出記錄時附上照片…」
    let items: [AlbumPhotoItem]

    private enum GroupMode: String, CaseIterable, Identifiable {
        case place = "依地點"
        case month = "依月份"
        case all = "全部"
        var id: String { rawValue }
    }

    @State private var groupMode: GroupMode = .place
    @State private var viewingPhotoURL: IdentifiableURL?
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy 年 M 月"; return f
    }()
    /// 月份分組 key 另用可排序格式，顯示文字才用 monthFmt（避免字串排序錯亂）
    private static let monthKeyFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
    }()

    /// 依目前分組模式產生 (標題, 照片) 區段；區段內照片一律新到舊
    private var sections: [(title: String, photos: [AlbumPhotoItem])] {
        switch groupMode {
        case .place:
            var order: [String] = []
            var map: [String: [AlbumPhotoItem]] = [:]
            // 地點順序依該地點最新照片日期排（最常去/最近去的排前面）
            for item in items.sorted(by: { $0.date > $1.date }) {
                let key = item.group.isEmpty ? "未命名地點" : item.group
                if map[key] == nil { order.append(key) }
                map[key, default: []].append(item)
            }
            return order.map { ($0, map[$0] ?? []) }
        case .month:
            var map: [String: [AlbumPhotoItem]] = [:]
            for item in items {
                map[Self.monthKeyFmt.string(from: item.date), default: []].append(item)
            }
            return map.keys.sorted(by: >).map { key in
                let photos = (map[key] ?? []).sorted { $0.date > $1.date }
                let title = photos.first.map { Self.monthFmt.string(from: $0.date) } ?? key
                return (title, photos)
            }
        case .all:
            return items.isEmpty ? [] : [("全部照片", items.sorted { $0.date > $1.date })]
        }
    }

    private var groupCount: Int { Set(items.map { $0.group.isEmpty ? "未命名地點" : $0.group }).count }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    albumEmptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summaryBar
                            Picker("分組", selection: $groupMode) {
                                ForEach(GroupMode.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            ForEach(sections, id: \.title) { section in
                                sectionHeader(section.title, count: section.photos.count)
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(section.photos) { photo in
                                        Button {
                                            viewingPhotoURL = IdentifiableURL(url: photo.url)
                                        } label: {
                                            AsyncThumbnailView(url: photo.url, size: CGSize(width: 104, height: 104))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .sheet(item: $viewingPhotoURL) { wrapper in PhotoLightbox(url: wrapper.url) }
        }
    }

    // MARK: 摘要列 / 區段標題

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
            Text("共 \(items.count) 張照片")
                .font(.subheadline.weight(.semibold))
            Text("\(groupCount) 個地點")
                .font(.caption.weight(.semibold)).foregroundStyle(accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(accent.opacity(0.12)).clipShape(Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.6))
            Spacer()
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 15)
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            Text("\(count)")
                .font(.caption2.weight(.semibold)).foregroundStyle(accent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.12)).clipShape(Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: 空狀態（雙層脈衝光環，對齊各地圖既有規格）

    private var albumEmptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.25), lineWidth: 1.5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.35 : 1.0)
                    .animation(.easeOut(duration: 2.0).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .stroke(accent.opacity(emptyIconPulse ? 0 : 0.13), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .scaleEffect(emptyIconPulse ? 1.60 : 1.0)
                    .animation(.easeOut(duration: 2.0).delay(0.3).repeatForever(autoreverses: false), value: emptyIconPulse)
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.50)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 0.75))
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .onAppear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
                emptyIconPulseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    emptyIconPulse = true
                }
            }
            .onDisappear {
                emptyIconPulseTask?.cancel()
                emptyIconPulse = false
            }

            Text(emptyTitle)
                .font(.headline)
            Text(emptyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
