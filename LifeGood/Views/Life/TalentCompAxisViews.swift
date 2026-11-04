import SwiftUI

// MARK: - [v25.603 職能雷達 v3] 人才矩陣縱軸切換用的小畫面（G2 負責；radar/judge_v3.md §C；radar/build/v3/brief.md §4 G2）
//
// • 人才矩陣（TalentMatrixView，G1）第一個分頁上面多「縱軸：潛力｜本職學能｜人格特質」；縱軸是職能時多：
//   圖下面一行「還沒評本職學能：張家瑋（1 位）」、圖例下面「兩種看法不一樣的人」卡、明細卡「本職學能 58.3（評了 9 格）」〔看職能〕。
// • 這個檔只排版：數字、字全部是 CompetencyMath.matrixAxis 算好的（CompMatrixAxis）；這個檔不寫任何 store、不讀潛力或主動性。
// • 看不擋訂閱（〔看職能〕打開的 SubordinateCompetencyTab 自己會擋評分）。sheet 由 TalentMatrixView 用 sheet(item:)＋.appStores() 開。
// • 名字、分數只在 App 裡：通知、小工具、手錶、鎖定畫面、靈動島一個字都不加。字不用「他／她」：用名字或「這位同仁」。
// 骨架（主控）：下面每個型別的名字、init 參數是跨組契約（TalentMatrixView 在叫），G2 只准改 body 與 private 的東西，不准改參數。
// 要退回這一版：TalentMatrixView 照 b793501，這個檔連同 pbxproj 四處（A01A／A01B000001001646）拿掉。

/// 縱軸看哪一個（不記住：每次打開人才矩陣都從潛力開始）
enum TalentCompAxis: String, Equatable, CaseIterable, Identifiable {
    case potential
    case skill
    case trait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .potential: return "潛力"
        case .skill:     return "本職學能"
        case .trait:     return "人格特質"
        }
    }

    /// 職能那一區（潛力 nil）
    var area: CompetencyTeamArea? {
        switch self {
        case .potential: return nil
        case .skill:     return .skill
        case .trait:     return .trait
        }
    }

    /// 切換列要列的（潛力永遠在第一個；areas＝LifeStore.competencyMatrixOptions，照「本職學能、人格特質」順序）
    static func options(_ areas: [CompetencyTeamArea]) -> [TalentCompAxis] {
        var out: [TalentCompAxis] = [.potential]
        if areas.contains(.skill) { out.append(.skill) }
        if areas.contains(.trait) { out.append(.trait) }
        return out
    }
}

/// 〔看職能〕：用 sheet 包那位的〔職能〕分頁（不改 SubordinateDetailView）
struct TalentCompPersonRequest: Identifiable {
    let id: UUID
    /// 導覽列標題（空白＝「這位同仁」）
    let name: String
}

/// TalentMatrixView body 上掛的〔看職能〕sheet＋匯出前的確認（拆成 modifier，body 的修飾器鏈才不會太長）。
/// onExport＝使用者按〔分享〕：TalentMatrixView 傳 `{ Task { @MainActor in exportJPG() } }`（alert 關好、下一輪才匯出）
struct TalentCompMatrixSheets: ViewModifier {
    @Binding var compPerson: TalentCompPersonRequest?
    @Binding var confirmExport: Bool
    /// 「圖上有名字和本職學能分數，確定要分享嗎？」（CompMatrixAxis.exportConfirmText；縱軸是潛力時不會出現）
    let confirmText: String
    let onExport: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $compPerson) { r in
                TalentCompPersonSheet(request: r)
                    .appStores()
            }
            .alert(confirmText, isPresented: $confirmExport) {
                Button("取消", role: .cancel) { }
                Button("分享") { onExport() }
            }
    }
}

/// 「縱軸：潛力｜本職學能｜人格特質」（segmented）
/// 左右外距跟上面的分頁 Picker 一樣（.padding(.horizontal)）；iPhone SE 三段字放不下時 segmented 自己縮字，不另外截字。
/// VoiceOver：前面的「縱軸」字不唸（Picker 自己唸「縱軸，潛力」）。
struct TalentCompAxisPicker: View {
    @Binding var selection: TalentCompAxis
    let options: [TalentCompAxis]

    /// 現在的縱軸不在選項裡（例：〔看職能〕→〔職能項目設定〕把人格項目都停用了）：圖已經照潛力畫
    ///（TalentMatrixView.axisContext 的 guard），切換列也標潛力，不會一段都沒選
    private var shownSelection: Binding<TalentCompAxis> {
        let b: Binding<TalentCompAxis> = $selection
        let opts: [TalentCompAxis] = options
        return Binding<TalentCompAxis>(
            get: { opts.contains(b.wrappedValue) ? b.wrappedValue : .potential },
            set: { b.wrappedValue = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("縱軸")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)
            Picker("縱軸", selection: shownSelection) {
                ForEach(options) { o in
                    Text(o.title).tag(o)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("縱軸")
        }
        .padding(.horizontal)
    }
}

/// 圖下面一行「還沒評本職學能：張家瑋（1 位）」（左右對齊圖卡裡面的字：外距 16＋4；多行可換行）
struct TalentCompUnratedLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }
}

/// 象限名字 → 顏色（照 TalentMatrixView.quadrantLabel：明星 green、潛力股 blue、苦勞型 orange、待加強 red）
private func talentCompQuadrantColor(_ quadrant: String) -> Color {
    switch quadrant {
    case "明星":   return .green
    case "潛力股": return .blue
    case "苦勞型": return .orange
    case "待加強": return .red
    default:       return .gray
    }
}

/// 「兩種看法不一樣的人」卡（圖例下面；點一列＝在圖上選那個人、打開原本的明細卡）
/// 樣式照 quadrantLegend：白底 16 圓角、0.75 邊框、shadow 0.06、頂上 4×16 漸層側條＋圖示＋粗體標題＋右邊「N 人」膠囊。
struct TalentCompDiffCard: View {
    let axis: CompMatrixAxis
    let onSelect: (UUID) -> Void

    /// 第一列上面不畫細線
    private var firstRowId: UUID? { axis.diffRows.first?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TalentCompDiffHeader(count: axis.diffRows.count)
            if let e = axis.diffEmptyText {
                Text(e)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
            ForEach(axis.diffRows) { row in
                TalentCompDiffRowView(row: row, areaName: axis.axisName,
                                      showsDivider: row.id != firstRowId, onSelect: onSelect)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator).opacity(0.10), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }
}

/// 卡片頂上：側條＋圖示＋「兩種看法不一樣的人」＋「N 人」（0 人不顯示膠囊）
private struct TalentCompDiffHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LinearGradient(colors: [.indigo, .indigo.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)   // 裝飾圖示：標題列唸「兩種看法不一樣的人，1 人」就好
            Text("兩種看法不一樣的人")
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count) 人")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 象限色小膠囊「潛力看：待加強」
private struct TalentCompQuadrantCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.5))
    }
}

/// 一列：「林志豪〔潛力看：待加強〕〔本職學能看：潛力股〕」＋小字原因＋右邊 chevron；整列一個 VoiceOver 元素
private struct TalentCompDiffRowView: View {
    let row: CompMatrixDiffRow
    /// 「本職學能」「人格特質」（CompMatrixAxis.axisName）
    let areaName: String
    let showsDivider: Bool
    let onSelect: (UUID) -> Void

    private var potentialText: String { "潛力看：\(row.potentialQuadrant)" }
    private var areaText: String { "\(areaName)看：\(row.areaQuadrant)" }

    /// 「林志豪，潛力看：待加強，本職學能看：潛力股。本職學能 58.3，在能獨立 50 以上；潛力 86，在中線 94.5 以下」
    private var voiceText: String {
        "\(row.name)，\(potentialText)，\(areaText)。\(row.reason)"
    }

    private var nameText: some View {
        Text(row.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var potentialCapsule: TalentCompQuadrantCapsule {
        TalentCompQuadrantCapsule(text: potentialText, color: talentCompQuadrantColor(row.potentialQuadrant))
    }

    private var areaCapsule: TalentCompQuadrantCapsule {
        TalentCompQuadrantCapsule(text: areaText, color: talentCompQuadrantColor(row.areaQuadrant))
    }

    /// 名字＋兩顆膠囊：一排放得下就一排；放不下（小螢幕、大字）名字一行、膠囊一行；再放不下一顆一行
    private var firstLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                nameText
                potentialCapsule
                areaCapsule
            }
            VStack(alignment: .leading, spacing: 4) {
                nameText
                HStack(spacing: 6) {
                    potentialCapsule
                    areaCapsule
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                nameText
                potentialCapsule
                areaCapsule
            }
        }
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                firstLine
                Text(row.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
                    .padding(.leading, 16)
                    .accessibilityHidden(true)
            }
            Button {
                onSelect(row.id)
            } label: {
                rowLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceText)   // Button 本身就是一個元素；整列唸一次
            .accessibilityHint("在圖上看這位")
        }
    }
}

/// 明細卡那一格：indigo 淺底膠囊「本職學能 58.3（評了 9 格）」＋右邊〔看職能〕（寬 320 的明細卡放得下；字太長縮到 0.8）
struct TalentCompDetailRow: View {
    let text: String
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.indigo.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.indigo.opacity(0.22), lineWidth: 0.5))
            Spacer(minLength: 4)
            Button("看職能") { onOpen() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)
                .tint(.indigo)
                .fixedSize()
                .accessibilityHint("打開這位的職能分頁")
        }
        .padding(.bottom, 10)
    }
}

/// 〔看職能〕那位的〔職能〕分頁（TalentMatrixView 用 sheet(item:)＋.appStores() 開；照 CompetencyTeamView 的 CompTeamPersonSheet；不包第二層 sheet）
struct TalentCompPersonSheet: View {
    let request: TalentCompPersonRequest

    @Environment(\.dismiss) private var dismiss

    /// 導覽列標題（空白＝「這位同仁」）
    private var title: String {
        let t = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "這位同仁" : t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SubordinateCompetencyTab(subordinateId: request.id)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
