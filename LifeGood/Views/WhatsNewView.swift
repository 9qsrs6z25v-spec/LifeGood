import SwiftUI

// MARK: - 本次更新
//
// [v25.392] 更新版本後第一次打開 App、開場動畫謝幕之後跳出來的視窗。
//
// 顯示「上次看過的版本」到「目前版本」之間的所有更新內容：
// 上次 25.389 → 現在 25.390 就只顯示 25.390；
// 上次 25.380 → 現在 25.390 就一次顯示 25.381～25.390。
// 決定要顯示哪幾版的邏輯在 Changelog.entries(after:upTo:)，觸發在 LifeGoodApp.LaunchGate。

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [ChangelogEntry]
    /// 關閉時呼叫（由呼叫端記下「已看到哪一版」）
    let onDone: () -> Void

    @State private var headerAppeared = false
    @State private var listAppeared = false

    init(entries: [ChangelogEntry], onDone: @escaping () -> Void) {
        self.entries = entries
        self.onDone = onDone
    }

    /// 品牌色：與開場動畫同一組漸層，讓這個視窗看起來是開場的延續
    private let brandBlue = Color(red: 0.16, green: 0.45, blue: 0.94)
    private let brandTeal = Color(red: 0.10, green: 0.68, blue: 0.62)

    var body: some View {
        NavigationStack {
            ScrollView {
                // LazyVStack 而不是 VStack：內建更新紀錄目前有 700 多筆，使用者若是
                // 從很舊的版本一路更新上來，一次要列的版本可能是幾十上百張卡片。
                // 一般 VStack 會在開窗當下就把全部建出來。
                LazyVStack(spacing: 14) {
                    header
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        versionCard(entry, index: idx)
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("本次更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { finish() }.bold()
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    finish()
                } label: {
                    Text("開始使用")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [brandBlue, brandTeal],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: brandBlue.opacity(0.28), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .padding(.top, 6)
                .background(.ultraThinMaterial)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { headerAppeared = true }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.12)) {
                    listAppeared = true
                }
            }
            // 掛在 onDisappear 而不是各個按鈕上：下拉關閉也要記下已讀，
            // 否則用下拉關掉的人下次開 App 又會跳同一份
            .onDisappear { onDone() }
        }
    }

    private func finish() {
        // onDone 交給 onDisappear 呼叫，這裡只負責關窗——
        // 兩邊都叫會讓呼叫端收到兩次（它是冪等的，但沒必要）
        dismiss()
    }

    // MARK: 標頭

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Image(systemName: "sparkles")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subheadline)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [brandBlue, brandTeal],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.10)).blur(radius: 18)
                    .frame(width: 140, height: 140).offset(x: 110, y: -50)
                Circle().fill(Color.white.opacity(0.08)).blur(radius: 12)
                    .frame(width: 90, height: 90).offset(x: -120, y: 46)
                Circle().fill(Color.white.opacity(0.06)).blur(radius: 8)
                    .frame(width: 55, height: 55).offset(x: 60, y: 56)
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: brandBlue.opacity(0.26), radius: 12, x: 0, y: 6)
        .padding(.horizontal)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 16)
    }

    /// 字串在 ViewBuilder 外組好（本專案踩過 SwiftUI 型別推導逾時）
    private var headline: String {
        guard let newest = entries.first else { return "已是最新版本" }
        return "更新到 v" + newest.version
    }

    private var subheadline: String {
        let noteCount = entries.reduce(0) { $0 + $1.notes.count }
        if entries.count <= 1 { return "這一版有 \(noteCount) 項變更" }
        // 一次跨了好幾版：把區間講清楚，使用者才知道為什麼一次看到這麼多
        let oldest = entries[entries.count - 1].version
        let newest = entries[0].version
        return "距離上次開啟已更新 \(entries.count) 個版本（v\(oldest) – v\(newest)），共 \(noteCount) 項變更"
    }

    // MARK: 單一版本

    private func versionCard(_ entry: ChangelogEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [brandBlue, brandBlue.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Text("v" + entry.version)
                    .font(.subheadline.weight(.bold))
                Text("build \(entry.build)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                Spacer()
                Text(entry.date)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entry.notes.enumerated()), id: \.offset) { i, note in
                    noteRow(note)
                    if i < entry.notes.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .opacity(listAppeared ? 1 : 0)
        .offset(y: listAppeared ? 0 : 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.84)
            .delay(min(0.05 * Double(index), 0.4)), value: listAppeared)
    }

    private func noteRow(_ note: String) -> some View {
        let parsed = NoteTag.split(note)
        return HStack(alignment: .top, spacing: 9) {
            if let tag = parsed.tag {
                Text(tag.title)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(tag.color.opacity(0.13))
                    .foregroundStyle(tag.color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(tag.color.opacity(0.22), lineWidth: 0.6))
            } else {
                Circle()
                    .fill(LinearGradient(colors: [brandBlue, brandTeal],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            }
            Text(parsed.body)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

// MARK: - 更新紀錄的【分類】標籤

/// 更新紀錄的慣例是用「【新增】…」開頭。把那個前綴拆出來做成彩色膠囊，
/// 一眼就分得出新功能、修 bug 還是說明；沒有前綴的舊紀錄照樣顯示，只是改用圓點。
enum NoteTag: String, CaseIterable {
    case added = "新增"
    case fixed = "修正"
    case note = "說明"
    case beauty = "美化"
    case feature = "功能"
    case repaired = "修復"
    case debug = "靜態除錯"

    var title: String { rawValue }

    var color: Color {
        switch self {
        case .added, .feature: return .green
        case .fixed, .repaired: return .orange
        case .note:            return .blue
        case .beauty:          return .purple
        case .debug:           return .red
        }
    }

    /// 把「【新增】內容」拆成（標籤, 內容）。認不出來的前綴不硬拆，整句原樣顯示。
    static func split(_ note: String) -> (tag: NoteTag?, body: String) {
        guard note.hasPrefix("【"), let close = note.firstIndex(of: "】") else {
            return (nil, note)
        }
        let raw = String(note[note.index(after: note.startIndex)..<close])
        let body = String(note[note.index(after: close)...])
        // 有些紀錄寫成「【靜態除錯 v24.39：修復 2 處真實 Bug】」，取開頭比對就好
        let matched = NoteTag.allCases.first { raw.hasPrefix($0.rawValue) }
        guard let matched else { return (nil, note) }
        return (matched, body.isEmpty ? note : body)
    }
}
