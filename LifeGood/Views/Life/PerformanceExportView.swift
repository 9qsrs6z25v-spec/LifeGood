import SwiftUI
import UIKit

// MARK: - 績效互評的出圖版面（v25.374）
//
// 兩種內容：
//   1. PerformanceBallotExportView — 某個人填的那張票（他把大家排成什麼順序）
//   2. PerformanceSummaryExportView — 年度評分加總（可只出指定的人）
//
// 兩者都是「靜態版面」：沒有捲軸、沒有可點元件、字串一律在 ViewBuilder 外組好，
// 交給 ImageRenderer 出圖。寬度固定 430pt，與部屬卡片／部屬總覽的出圖規格一致。

private let exportWidth: CGFloat = 430

// MARK: - 共用零件

private struct ExportHeader: View {
    let title: String
    let subtitle: String
    var accent: Color = .orange

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "trophy.fill")
                .font(.system(size: 22)).foregroundStyle(accent.opacity(0.8))
        }
        .padding(.horizontal, 16)
    }
}

private struct ExportFooter: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 9))
                Text("美好人生").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(PerformanceExporter.stampText()).font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
            Text(note)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }
}

private struct ExportCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.14), lineWidth: 0.75))
            .padding(.horizontal, 16)
    }
}

private struct ExportStatCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(color.opacity(0.14), lineWidth: 0.75))
    }
}

private func rankBadge(_ rank: Int, size: CGFloat = 30) -> some View {
    let color: Color = {
        switch rank {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }()
    return ZStack {
        Circle().fill(color.opacity(rank <= 3 ? 0.18 : 0.10)).frame(width: size, height: size)
        Text("\(rank)")
            .font(.system(size: size * 0.44, weight: .black, design: .rounded))
            .foregroundStyle(color)
    }
}

// MARK: - 1. 單張票

/// 某位評分者填的排名票。用來回答「他把大家排成什麼順序」。
struct PerformanceBallotExportView: View {
    let ballot: PerformanceBallot

    init(ballot: PerformanceBallot) { self.ballot = ballot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExportHeader(title: headerTitle, subtitle: headerSubtitle)
            raterCard
            ForEach(ballot.groups) { group in
                groupCard(group)
            }
            ExportFooter(note: Self.note)
        }
        .padding(.vertical, 20)
        .frame(width: exportWidth)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: 版塊

    private var raterCard: some View {
        ExportCard {
            HStack(spacing: 8) {
                Text(ballot.raterName.isEmpty ? "未命名" : ballot.raterName)
                    .font(.subheadline.weight(.bold))
                tag(ballot.raterGradeLabel.isEmpty ? "未設職等" : ballot.raterGradeLabel, .indigo)
                tag("權重 ×" + PerformanceExporter.num(ballot.raterWeight), .orange)
                if ballot.rankSharePercent > 0 {
                    tag("占比 " + PerformanceExporter.num(ballot.rankSharePercent) + "%", .teal)
                }
                Spacer(minLength: 0)
                tag(ballot.isSubmitted ? "已送出" : "草稿", ballot.isSubmitted ? .green : .secondary)
            }
        }
    }

    private func groupCard(_ group: PerformanceRankGroup) -> some View {
        let n = group.entries.count
        return ExportCard {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3.5, height: 14)
                Text(group.title).font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                tag("\(n) 人", .orange)
            }
            .padding(.bottom, 8)

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                entryRow(entry, rank: idx + 1, groupSize: n)
                if idx < n - 1 {
                    Divider().padding(.leading, 40).padding(.vertical, 5)
                }
            }
        }
    }

    private func entryRow(_ entry: PerformanceRankEntry, rank: Int, groupSize: Int) -> some View {
        let base = max(0, groupSize - rank + 1)
        let points = Double(base) * ballot.raterWeight
        return HStack(spacing: 10) {
            rankBadge(rank)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name.isEmpty ? "未命名" : entry.name)
                    .font(.subheadline.weight(.semibold))
                Text(pointLine(base: base))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(PerformanceExporter.num(points))
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.13)).foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: 字串（一律在 ViewBuilder 外組好）

    private var headerTitle: String {
        "\(String(ballot.year)) 年度績效互評"
    }

    private var headerSubtitle: String {
        let name = ballot.raterName.isEmpty ? "未命名" : ballot.raterName
        var parts = ["\(name) 的排名票", "\(ballot.groups.count) 組", "\(ballot.rankedCount) 人"]
        if let at = ballot.submittedAt {
            parts.append("送出於 " + PerformanceExporter.stampText(at))
        }
        return parts.joined(separator: "・")
    }

    private func pointLine(base: Int) -> String {
        "基礎 \(base) 分 × 權重 " + PerformanceExporter.num(ballot.raterWeight)
    }

    private static let note =
        "排名在「同課 × 同職等」的組內進行，某組 N 人時第 1 名基礎分 N、往下每名少 1 分，"
        + "再乘上評分者職等的績效權重。此圖為單一評分者的票，不是年度加總結果。"
}

// MARK: - 2. 評分加總

/// 年度評分加總。personIds 為空＝全部；有值＝只出這些人（其餘照樣參與計分，只是不列出）。
struct PerformanceSummaryExportView: View {
    let year: Int
    let sections: [PerformanceGradeSection]
    let share: PerformanceShare
    let submittedCount: Int
    let pendingNames: [String]
    let scopeLabel: String
    /// 只列出這些人；空集合＝全部
    let personIds: Set<UUID>
    /// [v25.375] 要不要把「誰給的分數」顯示成真實姓名。
    /// 關掉時所有評分者一律顯示成「評分者 A／B／C……」，尚未送出的名單也只出人數——
    /// 這張圖多半是要給別人看的，誰把誰排在後面很容易變成嫌隙。
    let showRaterNames: Bool

    init(year: Int, sections: [PerformanceGradeSection], share: PerformanceShare,
         submittedCount: Int, pendingNames: [String], scopeLabel: String,
         personIds: Set<UUID>, showRaterNames: Bool) {
        self.year = year
        self.sections = sections
        self.share = share
        self.submittedCount = submittedCount
        self.pendingNames = pendingNames
        self.scopeLabel = scopeLabel
        self.personIds = personIds
        self.showRaterNames = showRaterNames
    }

    /// 匿名代號表。以 UUID 排序建立，跟姓名、職等、名次都無關，
    /// 所以看圖的人推不回是誰；同一張圖裡同一個評分者的代號一致。
    private var anonymousNames: [UUID: String] {
        var ids = Set(share.votes.map(\.raterId))
        for sec in sections {
            for score in sec.scores {
                for src in score.sources { ids.insert(src.raterId) }
            }
        }
        var out: [UUID: String] = [:]
        for (i, id) in ids.sorted(by: { $0.uuidString < $1.uuidString }).enumerated() {
            out[id] = "評分者 " + Self.letter(i)
        }
        return out
    }

    /// 0→A、25→Z、26→A2、27→B2……（超過 26 人才會用到後綴）
    private static func letter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let base = String(letters[index % 26])
        let round = index / 26
        return round == 0 ? base : base + String(round + 1)
    }

    private func raterLabel(_ id: UUID, fallback: String) -> String {
        if showRaterNames { return fallback.isEmpty ? "未命名" : fallback }
        return anonymousNames[id] ?? "評分者"
    }

    /// 套用「只出這些人」之後還有內容的分段
    private var shownSections: [PerformanceGradeSection] {
        guard !personIds.isEmpty else { return sections }
        return sections.compactMap { sec in
            // 名次要維持在完整職等裡的名次，所以先編號再篩選
            let kept = sec.scores.filter { personIds.contains($0.personId) }
            guard !kept.isEmpty else { return nil }
            return PerformanceGradeSection(gradeId: sec.gradeId, label: sec.label,
                                           weight: sec.weight, scores: kept)
        }
    }

    /// 某個人在他所屬職等裡的名次（以完整名單計算，篩選不會讓名次跑掉）
    private func rank(of personId: UUID, in section: PerformanceGradeSection) -> Int {
        guard let full = sections.first(where: { $0.id == section.id }),
              let idx = full.scores.firstIndex(where: { $0.personId == personId }) else { return 0 }
        return idx + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExportHeader(title: "\(String(year)) 年度 評分加總", subtitle: headerSubtitle)
            kpiBlock
            if share.isConfigured { shareCard }
            ForEach(shownSections) { section in
                gradeBlock(section)
            }
            if !pendingNames.isEmpty {
                ExportCard {
                    Text(pendingLine)
                        .font(.system(size: 10)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ExportFooter(note: footerNote)
        }
        .padding(.vertical, 20)
        .frame(width: exportWidth)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: 版塊

    private var kpiBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ExportStatCell(value: "\(submittedCount)", label: "已送出票", color: .green)
                ExportStatCell(value: "\(pendingNames.count)", label: "尚未送出",
                               color: pendingNames.isEmpty ? .secondary : .orange)
                ExportStatCell(value: "\(ratedCount)", label: "被評分人數", color: .blue)
            }
            HStack(spacing: 8) {
                ExportStatCell(value: PerformanceExporter.num(share.rankPercent) + "%",
                               label: "排名平均占比", color: .orange)
                ExportStatCell(value: PerformanceExporter.num(share.overallPercent) + "%",
                               label: "總分占比", color: .purple)
            }
        }
        .padding(.horizontal, 16)
    }

    private var shareCard: some View {
        ExportCard {
            Text("占比來源（依評分者職等權重加權平均）")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            ForEach(share.votes) { v in
                HStack(spacing: 8) {
                    Text(raterLabel(v.raterId, fallback: v.raterName))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 66, alignment: .leading).lineLimit(1)
                    if showRaterNames {
                        Text(v.raterGradeLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(PerformanceExporter.num(v.percent) + "% × "
                         + PerformanceExporter.num(v.weight))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            Divider().padding(.vertical, 5)
            HStack {
                Text("加權平均").font(.system(size: 10, weight: .bold))
                Spacer()
                Text(shareFormula).font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gradeBlock(_ section: PerformanceGradeSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.orange, .orange.opacity(0.35)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3.5, height: 14)
                Text(section.label).font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                if let w = section.weight {
                    Text("權重 ×" + PerformanceExporter.num(w))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            if let basis = basisLine(section) {
                Text(basis).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            ForEach(section.scores) { score in
                scoreRow(score, rank: rank(of: score.personId, in: section))
            }
        }
        .padding(.horizontal, 16)
    }

    private func scoreRow(_ score: PerformanceScore, rank: Int) -> some View {
        ExportCard {
            HStack(spacing: 10) {
                rankBadge(rank, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.name.isEmpty ? "未命名" : score.name)
                        .font(.subheadline.weight(.bold))
                    Text(metaLine(score))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(PerformanceExporter.num(score.finalScore))
                            .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                        Text("/").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        Text(PerformanceExporter.num(score.rawFinalScore))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("正規化 / 原始")
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            Divider().padding(.vertical, 7)
            Text(formulaLine(score))
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // 每張票給了第幾名
            if !score.sources.isEmpty {
                Text("各票名次")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    .padding(.top, 6).padding(.bottom, 2)
                ForEach(score.sources.sorted { $0.points > $1.points }) { src in
                    HStack(spacing: 6) {
                        Text(raterLabel(src.raterId, fallback: src.raterName))
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 62, alignment: .leading).lineLimit(1)
                        Text("第 \(src.rank)/\(src.groupSize) 名")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.10)).foregroundStyle(.blue)
                            .clipShape(Capsule())
                        Spacer(minLength: 0)
                        Text(PerformanceExporter.num(src.points))
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 1.5)
                }
            }
        }
    }

    // MARK: 字串

    private var ratedCount: Int {
        sections.reduce(0) { $0 + $1.scores.count }
    }

    private var headerSubtitle: String {
        var parts: [String] = [scopeLabel]
        if personIds.isEmpty {
            parts.append("全部 \(ratedCount) 人")
        } else {
            let shown = shownSections.reduce(0) { $0 + $1.scores.count }
            parts.append("指定 \(shown) 人")
        }
        if !share.isConfigured { parts.append("占比未設定") }
        if !showRaterNames { parts.append("評分者匿名") }
        return parts.joined(separator: "・")
    }

    /// 尚未送出的人：匿名時只講人數，不點名
    private var pendingLine: String {
        guard showRaterNames else { return "尚未送出：\(pendingNames.count) 人" }
        return "尚未送出：" + pendingNames.joined(separator: "、")
    }

    private var shareFormula: String {
        let numerator = share.votes.reduce(0.0) { $0 + $1.weighted }
        return PerformanceExporter.num(numerator) + " ÷ " + PerformanceExporter.num(share.weightSum)
            + " = " + PerformanceExporter.num(share.rankPercent) + "%"
    }

    private func basisLine(_ section: PerformanceGradeSection) -> String? {
        guard let s = section.scores.first, s.rankBasis > 0 || s.overallBasis > 0 else { return nil }
        return "100 分基準：排名 " + PerformanceExporter.num(s.rankBasis)
            + "、綜合 " + PerformanceExporter.num(s.overallBasis) + "（本職等最高，不分課別）"
    }

    private func metaLine(_ score: PerformanceScore) -> String {
        var parts: [String] = ["\(score.sources.count) 票"]
        parts.append(String(format: "平均第 %.1f 名", score.averageRank))
        parts.append("排名 " + PerformanceExporter.num(score.total))
        parts.append("綜合 " + PerformanceExporter.num(score.overallScore))
        if !score.hasOverall { parts.append("已轉出") }
        return parts.joined(separator: "・")
    }

    private func formulaLine(_ score: PerformanceScore) -> String {
        let a = PerformanceExporter.num(score.normalizedRank) + " × "
            + PerformanceExporter.num(share.rankPercent) + "%"
        let b = PerformanceExporter.num(score.normalizedOverall) + " × "
            + PerformanceExporter.num(share.overallPercent) + "%"
        return "正規化：" + a + " ＋ " + b + " = " + PerformanceExporter.num(score.finalScore)
            + "　／　未正規化：" + PerformanceExporter.num(score.rawFinalScore)
    }

    private var footerNote: String {
        guard showRaterNames else { return Self.note + Self.anonymousNote }
        return Self.note
    }

    private static let note =
        "最終分數＝正規化排名 × 排名平均占比 ＋ 正規化綜合 ×（1 − 占比）。"
        + "正規化是每個職等各自把兩段分數除以該職等最高分再乘 100，所以每個職等的第一名都是 100 分、"
        + "跨職等不能直接比較；右邊的原始值才看得出實際的量。"

    private static let anonymousNote =
        "　評分者已匿名，代號與姓名、職等、名次無關。"
}

// MARK: - 出圖

enum PerformanceExporter {
    /// 出成 JPG（過長自動切頁，比照部屬總覽）。失敗回空陣列。
    @MainActor
    static func jpg<V: View>(_ view: V, name: String) -> [URL] {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .unspecified
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage else { return [] }
        let pages = SubordinateOverviewView.sliceTallImage(ui, maxPageHeightPt: 1600)
        var urls: [URL] = []
        for (i, page) in pages.enumerated() {
            guard let data = page.jpegData(compressionQuality: 0.95) else { continue }
            let suffix = pages.count > 1 ? "_\(i + 1)之\(pages.count)" : ""
            let safe = name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safe)\(suffix).jpg")
            do {
                try data.write(to: url)
                urls.append(url)
            } catch { continue }
        }
        return urls
    }

    /// 整數就不帶小數點，其餘留一位
    static func num(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func stampText(_ date: Date = Date()) -> String {
        stampFmt.string(from: date)
    }

    static let fileStampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()

    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
}
