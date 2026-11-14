import SwiftUI

// MARK: - [v25.605 職能雷達 v4b] 課的總覽分享的圖片（熱力表出圖專用、純靜態；radar/judge_v4b.md §C3；radar/build/v4b/brief.md §4 G2）
//
// • 照畫面上那一份 CompetencyTeamModel（目前的區、部門篩選、〔含已轉出〕）畫；欄照 CompetencyMath.heatSharePages 切
//  （每張最多 12 欄、名字欄與能獨立／能教人／課平均三列每張都有）；標題＝page.title「廠務課・本職學能・2026/11/5（1／2）」。
// • 淺色、補環境物件照 SubExportImage.decorate（ImageRenderer 一張一張畫；ImageExportLimits.safeScale／isBlank）。
// • 格子：數字一定寫、五階底色（淺色那一組透明度）、—／·／／、◤ 未達目標；欄紅框橘框；欄頭兩列（組名、項目短名）。
// • 純靜態：沒有 Button、@State、@ScaledMetric、onAppear、動畫、GeometryReader；寬度全部寫死（CompTeamShare… 常數）。
// • §13：沒有評語。檔名不放名字、部門（CompetencyMath.heatShareFileName）。
// 骨架（主控）：CompetencyHeatShareImage.render(_:pages:now:) 是跨組契約（CompetencyTeamView 在叫），不准改簽名；內容由 G2 換成真的。
// G2（v25.605）：畫法換成 CompTeamSharePageView（名字欄＋每組一個 VStack＋一欄一個 VStack；列順序＝m.rows，不照畫面上的排序）。
// 要退回這一件：這個檔連同 pbxproj 四處（A01A／A01B000001001648）拿掉，課的總覽〔分享…〕那幾行拿掉。

enum CompetencyHeatShareImage {

    /// 一張一張畫成 JPG 存到暫存資料夾。urls＝出得來的；expected＝pages.count（少了就說「有 N 張出不來」）
    @MainActor
    static func render(_ m: CompetencyTeamModel, pages: [CompetencyHeatSharePage], now: Date) -> SubExportRenderResult {
        let cal: Calendar = SubExportComposer.gregorian
        let fileStamp: String = SubExportComposer.fileStamp(now, cal: cal)
        let stamp: String = "美好人生 · " + SubExportComposer.ymd(now, cal: cal) + " " + SubExportComposer.hm(now, cal: cal) + " 匯出"
        var urls: [URL] = []
        for p in pages {
            let page = CompTeamSharePageView(model: m, page: p, stamp: stamp)
            let renderer = ImageRenderer(content: SubExportImage.decorate(AnyView(page)))
            var measured = CGSize.zero
            renderer.render { size, _ in measured = size }
            renderer.scale = ImageExportLimits.safeScale(for: measured)
            guard let ui = renderer.uiImage, !ImageExportLimits.isBlank(ui),
                  let data = ui.jpegData(compressionQuality: 0.95) else { continue }
            let name: String = CompetencyMath.heatShareFileName(stamp: fileStamp, page: p.id, pages: pages.count)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try data.write(to: url)
                urls.append(url)
            } catch {
                continue
            }
        }
        return SubExportRenderResult(urls: urls, expected: pages.count)
    }
}

// MARK: - 尺寸（全部寫死；出圖時字級由 decorate 固定在 .large）

private enum CompTeamShareLayout {
    static let pad: CGFloat = 16
    static let nameWidth: CGFloat = 110
    static let colWidth: CGFloat = 44
    /// 一組裡左右的間距
    static let hSpacing: CGFloat = 3
    /// 組與組之間
    static let groupSpacing: CGFloat = 8
    /// 一欄裡上下的間距（名字欄也用這個）
    static let vSpacing: CGFloat = 2
    static let groupHeight: CGFloat = 20
    static let headerHeight: CGFloat = 36
    static let rowHeight: CGFloat = 32
    static let footHeight: CGFloat = 26
    /// 欄很少時標題、圖例、stamp 不要擠成好幾行（整張最窄這麼寬）
    static let minWidth: CGFloat = 360

    static let lightAlpha: [Double] = [0.10, 0.22, 0.36, 0.52, 0.70]

    /// 整張寬＝16×2＋110＋欄數×44＋(欄數−組數)×3＋(組數−1)×8（最窄 minWidth）
    static func pageWidth(columns: Int, groups: Int) -> CGFloat {
        let c: CGFloat = CGFloat(max(columns, 0))
        let g: CGFloat = CGFloat(max(groups, 1))
        let table: CGFloat = nameWidth + c * colWidth + max(0, c - g) * hSpacing + (g - 1) * groupSpacing
        return max(minWidth, pad * 2 + table)
    }

    /// 一組的組名寬＝這組幾欄
    static func groupWidth(_ n: Int) -> CGFloat {
        let k: CGFloat = CGFloat(max(n, 1))
        return k * colWidth + (k - 1) * hSpacing
    }
}

// MARK: - 一張圖

/// 一張：標題、表（名字欄＋這張的組）、圖例、右下匯出時間
private struct CompTeamSharePageView: View {
    let model: CompetencyTeamModel
    let page: CompetencyHeatSharePage
    let stamp: String

    private var columnCount: Int { max(0, page.end - page.start) }

    private var width: CGFloat {
        CompTeamShareLayout.pageWidth(columns: columnCount, groups: page.groups.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(page.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            CompTeamShareTable(model: model, page: page)
            Text(model.legend)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Text(stamp)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(CompTeamShareLayout.pad)
        .frame(width: width, alignment: .leading)
        .background(Color.white)
    }
}

/// 表：名字欄＋這張的每一組
private struct CompTeamShareTable: View {
    let model: CompetencyTeamModel
    let page: CompetencyHeatSharePage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CompTeamShareNameColumn(model: model)
            HStack(alignment: .top, spacing: CompTeamShareLayout.groupSpacing) {
                ForEach(page.groups) { g in
                    CompTeamShareGroupView(model: model, group: g, indices: indices(g))
                }
            }
        }
    }

    /// 這一組在這張的欄（page.groups 的 start 是這張裡面的位置 → 換回 columns 的位置；超出這張、超出 columns 的不畫）
    private func indices(_ g: CompetencyTeamGroupHeader) -> [Int] {
        let hiPage: Int = min(page.end, model.columns.count)
        let lo: Int = max(page.start, min(page.start + g.start, hiPage))
        let hi: Int = max(lo, min(page.start + g.start + g.count, hiPage))
        return Array(lo..<hi)
    }
}

/// 名字欄：兩列欄頭留白、每位一格（名字＋「E2」／「已轉出」）、最後三格列名
private struct CompTeamShareNameColumn: View {
    let model: CompetencyTeamModel

    var body: some View {
        VStack(alignment: .leading, spacing: CompTeamShareLayout.vSpacing) {
            Color.clear.frame(width: CompTeamShareLayout.nameWidth, height: CompTeamShareLayout.groupHeight)
            Color.clear.frame(width: CompTeamShareLayout.nameWidth, height: CompTeamShareLayout.headerHeight)
            ForEach(model.rows) { r in
                CompTeamShareNameCell(row: r)
            }
            CompTeamShareFootLabel(text: model.independentLabel)
            CompTeamShareFootLabel(text: model.trainerLabel)
            CompTeamShareFootLabel(text: "課平均")
        }
    }
}

private struct CompTeamShareNameCell: View {
    let row: CompetencyTeamRow

    private var displayName: String {
        let n: String = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "這位同仁" : n
    }

    /// 第二行：「E2」「已轉出」（沒設職等 nil）
    private var subline: String? {
        if row.archived { return "已轉出" }
        return row.gradeShort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(row.archived ? Color.secondary : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let s = subline {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: CompTeamShareLayout.nameWidth, height: CompTeamShareLayout.rowHeight, alignment: .leading)
    }
}

private struct CompTeamShareFootLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: CompTeamShareLayout.nameWidth, height: CompTeamShareLayout.footHeight, alignment: .leading)
    }
}

/// 一組：組名一列（寬＝這組在這張的欄數）＋一欄一個 VStack
private struct CompTeamShareGroupView: View {
    let model: CompetencyTeamModel
    let group: CompetencyTeamGroupHeader
    let indices: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: CompTeamShareLayout.vSpacing) {
            Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CompetencyPalette.tint(isTrait: group.isTrait))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: CompTeamShareLayout.groupWidth(indices.count),
                       height: CompTeamShareLayout.groupHeight, alignment: .leading)
            HStack(alignment: .top, spacing: CompTeamShareLayout.hSpacing) {
                ForEach(indices, id: \.self) { ci in
                    CompTeamShareColumnView(model: model, column: model.columns[ci], ci: ci, isTrait: group.isTrait)
                }
            }
        }
    }
}

/// 一欄：欄頭、每位一格、能獨立／能教人／課平均；整欄紅框（能獨立 ≤ 1）或橘框（能教人 ≤ 1）
private struct CompTeamShareColumnView: View {
    let model: CompetencyTeamModel
    let column: CompetencyTeamColumn
    let ci: Int
    let isTrait: Bool

    private var strokeColor: Color {
        if column.red { return Color.red }
        if column.orange { return Color.orange }
        return Color.clear
    }

    var body: some View {
        VStack(spacing: CompTeamShareLayout.vSpacing) {
            Text(column.itemTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: CompTeamShareLayout.colWidth, height: CompTeamShareLayout.headerHeight)
            ForEach(model.rows) { r in
                CompTeamShareRowCell(row: r, ci: ci, isTrait: isTrait)
            }
            CompTeamShareFootValue(text: column.independentText, color: column.red ? Color.red : Color.primary,
                                   bold: column.red)
            CompTeamShareFootValue(text: column.trainerText, color: column.orange ? Color.orange : Color.primary,
                                   bold: column.orange)
            CompTeamShareFootValue(text: column.averageText, color: Color.secondary, bold: false)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: 2))
    }
}

/// 一位在這一欄的格子（cells 不夠長時留白）
private struct CompTeamShareRowCell: View {
    let row: CompetencyTeamRow
    let ci: Int
    let isTrait: Bool

    var body: some View {
        if ci >= 0 && ci < row.cells.count {
            CompTeamShareCellView(cell: row.cells[ci], isTrait: isTrait, archived: row.archived)
        } else {
            Color.clear.frame(width: CompTeamShareLayout.colWidth, height: CompTeamShareLayout.rowHeight)
        }
    }
}

/// 能獨立／能教人／課平均那三列的一格
private struct CompTeamShareFootValue: View {
    let text: String
    let color: Color
    let bold: Bool

    var body: some View {
        Text(text)
            .font(bold ? Font.caption.weight(.bold) : Font.caption)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: CompTeamShareLayout.colWidth, height: CompTeamShareLayout.footHeight)
    }
}

/// 一格：數字一定寫、底色五階（淺色那一組）、—／·／／、◤ 未達目標（右上紅色小三角）
private struct CompTeamShareCellView: View {
    let cell: CompetencyTeamCell
    let isTrait: Bool
    let archived: Bool

    private var fill: Color {
        switch cell.kind {
        case .value:
            let list: [Double] = CompTeamShareLayout.lightAlpha
            let tier: Int = max(0, min(cell.tier ?? 0, list.count - 1))
            return CompetencyPalette.tint(isTrait: isTrait).opacity(list[tier])
        case .notRequired:
            return Color(white: 0.92)
        case .unrated, .na:
            return Color.clear
        }
    }

    /// 未評、不適用：透明底加一圈淡框，跟「—」灰底分得出
    private var borderColor: Color {
        (cell.kind == .unrated || cell.kind == .na) ? Color.gray.opacity(0.35) : Color.clear
    }

    private var textColor: Color {
        cell.kind == .value ? Color.primary : Color.secondary
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: 1)
            Text(cell.text)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if cell.belowTarget {
                CompTeamShareCornerMark()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: CompTeamShareLayout.colWidth, height: CompTeamShareLayout.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .opacity(archived ? 0.5 : 1)
    }
}

/// ◤ 未達目標：格子右上角的小直角三角形（照 CompetencyTeamView 的 CompTeamCornerMark 寫一份；那個是 private）
private struct CompTeamShareCornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
