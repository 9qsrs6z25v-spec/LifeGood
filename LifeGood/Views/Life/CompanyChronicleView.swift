import SwiftUI

// MARK: - 廠區編年史（v25.363）
//
// 把「廠區據點 + 掛在它底下的重大決議」畫成一張編年史圖，直式或橫式都可以。
// 純 SwiftUI 繪製（漸層、形狀、SF Symbols），不依賴任何圖片素材，
// 交給 ImageRenderer 出圖就能分享。
//
// 直式：左側一條時間軸，由上往下一個廠一段，決議列在各自那段底下。
// 橫式：由左至右一個廠一欄，適合廠多、每廠決議少的情況。

struct ChronicleEntry: Identifiable {
    let site: CompanySite
    /// 這個廠的期間結束（＝下一個廠啟用）；nil＝至今
    let eraEnd: Date?
    let resolutions: [SideRoleResolution]
    var id: UUID { site.id }
}

struct CompanyChronicleView: View {
    enum Orientation { case vertical, horizontal }

    let title: String
    let subtitle: String
    let entries: [ChronicleEntry]
    let orientation: Orientation
    /// 每個廠最多畫幾則決議，超過的只寫「還有 N 則」，避免圖爆長
    var maxResolutionsPerSite = 10

    private let ink = Color(red: 0.16, green: 0.13, blue: 0.11)
    private let accent = Color(red: 0.45, green: 0.31, blue: 0.20)   // 棕
    private let paper = Color(red: 0.99, green: 0.98, blue: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(accent.opacity(0.25)).frame(height: 2)
                .padding(.bottom, orientation == .vertical ? 22 : 26)
            if entries.isEmpty {
                Text("還沒有廠區據點")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.4))
                    .padding(.vertical, 60)
            } else if orientation == .vertical {
                verticalBody
            } else {
                horizontalBody
            }
            footer
        }
        .padding(orientation == .vertical ? 44 : 40)
        .frame(width: orientation == .vertical ? 900 : nil,
               alignment: .topLeading)
        .background(paper)
    }

    // MARK: 頁首頁尾

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ink.opacity(0.55))
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 3) {
                Text("編年史").font(.system(size: 13, weight: .bold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(accent)
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(accent.opacity(0.75))
            }
        }
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill").font(.system(size: 10))
            Text("美好人生").font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(Self.stamp.string(from: Date()) + " 匯出")
                .font(.system(size: 11))
        }
        .foregroundStyle(ink.opacity(0.38))
        .padding(.top, 26)
    }

    // MARK: 直式

    private var verticalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                HStack(alignment: .top, spacing: 18) {
                    spine(isLast: idx == entries.count - 1)
                    VStack(alignment: .leading, spacing: 10) {
                        siteHeading(entry)
                        resolutionList(entry)
                    }
                    .padding(.bottom, idx == entries.count - 1 ? 0 : 30)
                }
            }
        }
    }

    /// 時間軸：圓點 ＋ 往下的連續線
    private func spine(isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 18, height: 18)
                Circle().fill(paper).frame(width: 7, height: 7)
            }
            if !isLast {
                Rectangle()
                    .fill(accent.opacity(0.28))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 18)
    }

    private func siteHeading(_ entry: ChronicleEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eraText(entry))
                .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.site.name.isEmpty ? entry.site.displayName : entry.site.name)
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                if !entry.site.company.isEmpty {
                    Text(entry.site.company)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(accent)
                }
                if !entry.site.isActive {
                    Text("已結束")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(ink.opacity(0.08), in: Capsule())
                        .foregroundStyle(ink.opacity(0.45))
                }
            }
            HStack(spacing: 10) {
                if !entry.site.location.isEmpty {
                    label("mappin", entry.site.location)
                }
                label("doc.text", "\(entry.resolutions.count) 則決議")
                if let y = entry.site.years, y >= 0.1 {
                    label("clock", String(format: "%.1f 年", y))
                }
            }
        }
    }

    private func label(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(ink.opacity(0.5))
    }

    private func resolutionList(_ entry: ChronicleEntry) -> some View {
        let shown = Array(entry.resolutions.prefix(maxResolutionsPerSite))
        let rest = entry.resolutions.count - shown.count
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(shown) { r in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(accent.opacity(0.45))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(SideRoleFormat.date(r.date))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent.opacity(0.85))
                            if !r.serialLabel.isEmpty {
                                Text(r.serialLabel)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(ink.opacity(0.35))
                            }
                            Text(r.title.isEmpty ? "（未填標題）" : r.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !r.categories.isEmpty || !r.initiator.isEmpty {
                            Text(metaText(r))
                                .font(.system(size: 10))
                                .foregroundStyle(ink.opacity(0.42))
                        }
                    }
                }
            }
            if rest > 0 {
                Text("還有 \(rest) 則決議")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.35))
                    .padding(.leading, 13)
            }
            if entry.resolutions.isEmpty {
                Text("這段期間沒有記錄決議")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.3))
                    .padding(.leading, 13)
            }
        }
    }

    // MARK: 橫式

    private var horizontalBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 上方一條貫穿的時間軸
            HStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, _ in
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [accent, accent.opacity(0.65)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 16, height: 16)
                            Circle().fill(paper).frame(width: 6, height: 6)
                        }
                        if idx != entries.count - 1 {
                            Rectangle().fill(accent.opacity(0.28)).frame(height: 2)
                        }
                    }
                    .frame(width: 300, alignment: .leading)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 0) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        siteHeading(entry)
                        resolutionList(entry)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 278, alignment: .topLeading)
                    .padding(.trailing, 22)
                }
            }
        }
    }

    // MARK: 文字

    private func eraText(_ entry: ChronicleEntry) -> String {
        guard entry.site.startYear > 0 else { return "未填年月" }
        guard let end = entry.eraEnd else { return entry.site.startText + " ─ 至今" }
        let c = Calendar.current.dateComponents([.year, .month], from: end)
        return entry.site.startText + " ─ " + String(format: "%d/%02d", c.year ?? 0, c.month ?? 1)
    }

    private func metaText(_ r: SideRoleResolution) -> String {
        var parts: [String] = []
        if !r.categories.isEmpty { parts.append(r.categories.joined(separator: "、")) }
        if !r.initiator.isEmpty { parts.append("發起 " + r.initiator) }
        if !r.site.isEmpty { parts.append(r.site) }
        return parts.joined(separator: "・")
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()
}

// MARK: - 出圖

enum ChronicleExporter {
    /// 畫成 PNG 存到暫存檔，回傳可分享的 URL
    @MainActor
    static func png(_ view: CompanyChronicleView, name: String) -> URL? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
