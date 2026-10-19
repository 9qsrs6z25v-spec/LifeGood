import SwiftUI

// MARK: - 財富頁看板與看板下的各區（v25.564，財富 v3；wealth/judge.md §3.1、§3.3、§3.6、§3.11、§3.12）
//
// 看板外框自己組（照 HealthBoard）：MoneyBoardHeader（band 118，.towers）＋看板下（存款組成條＋四格）＋MoneyBoardChrome，
// 圓角讀 HeroCard.lifeFinance。接下來 30 天・各帳戶夠不夠扣、頁尾、新手大按鈕、「這頁的數字怎麼算」「iCloud 與家人共享說明」也在這裡。
//
// 分工：G1 實作。主控只開檔。
//
// [v25.564] G1：
// • WealthBoard(data:onTile:onStarter:)：頭部＝MoneyBoardHeader（日期「10/19 週一」、膠囊挑一件、小字、大字、一句、手寫、
//   頂樓水塔 .towers）；整個頭部一個 VoiceOver 元素念資料端組好的那一句（風景本來就 accessibilityHidden）。
//   看板下：存款組成條（MoneyShareRibbon＋MoneyLegendItem；點了捲到 ⑤）＋四格（MoneyTileGrid＋MoneyTile，一格只有圖示＋標籤／
//   大字／一行灰字，坑 #1；點了捲到那一區）；字放到 xxLarge 以上一列一格；只有一格（沒有卡）整列寬；
//   新手換三顆大按鈕〔＋ 薪轉帳戶〕〔＋ 信用卡〕〔＋ 保單〕（要訂閱：財富頁擋）。
// • WealthPageUpcomingSection：③ 接下來 30 天・各帳戶夠不夠扣（白卡；一個帳戶一列，點了開銀行頁捲到「接下來」；「看 6 件 ›」）。
// • WealthPageUpcomingSheet：「看 6 件」那張表單（FinanceLedgerRow：日期塊＋一句＋金額＋扣完剩多少；變負的整列 warn）。
// • WealthPageInfoSheet：⋯ 的兩張說明。WealthPageFooterView：⑨ 頁尾灰字（匯率太舊那句琥珀色）。

// MARK: - ① 看板

/// ① 看板（左右 16pt 由財富頁的 VStack 給）
struct WealthBoard: View {
    let data: WealthPageData
    /// 格子、圖例點了：捲到那一區
    let onTile: (WealthPageAnchor) -> Void
    /// 新手的三顆大按鈕
    let onStarter: (WealthAccountKind) -> Void

    @Environment(\.colorScheme) private var scheme
    /// 只讀「圓角」（同 HealthBoard／VehicleCardBoard：看板不吃英雄卡的漸層與 KPI 樣式）
    @ObservedObject private var heroStyle = HeroStyleStore.shared

    init(data: WealthPageData, onTile: @escaping (WealthPageAnchor) -> Void,
         onStarter: @escaping (WealthAccountKind) -> Void) {
        self.data = data
        self.onTile = onTile
        self.onStarter = onStarter
    }

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let corner = CGFloat(heroStyle.value(.corner, .lifeFinance))
        VStack(alignment: .leading, spacing: 0) {
            header(pal)
            if hasBelow {
                below(pal)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        .modifier(MoneyBoardChrome(pal: pal, corner: corner))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var hasBelow: Bool {
        data.mode == .newbie || data.ribbon != nil || !data.tiles.isEmpty
    }

    private func header(_ pal: TripBoardPalette) -> some View {
        let b = data.board
        let tint: Color? = b.capsuleTone == MoneyTone.neutral ? nil : b.capsuleTone.color(pal)
        let line: Text? = b.line.runs.isEmpty ? nil : FinanceLineText.text(b.line, pal: pal)
        return MoneyBoardHeader(
            date: b.date,
            dateIcon: "calendar",
            capsule: b.capsule,
            capsuleIcon: b.capsuleIcon,
            capsuleTint: tint,
            label: b.label,
            big: b.big,
            bigTone: b.bigTone,
            line: line,
            greeting: b.greeting,
            scene: .towers(data.tower),
            band: 118,
            seed: b.seed)
            // 整個頭部一個 VoiceOver 元素，唸資料端組好的那一句（風景本來就 accessibilityHidden）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.accessibilityText)
    }

    @ViewBuilder
    private func below(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = data.ribbon {
                WealthPageRibbonView(ribbon: r, pal: pal) { onTile(.banks) }
            }
            if data.mode == .newbie {
                WealthPageStarters(pal: pal, onStarter: onStarter)
            } else if !data.tiles.isEmpty {
                WealthPageTiles(tiles: data.tiles, pal: pal, onTile: onTile)
            }
        }
    }
}

/// 存款組成條＋一行圖例（點了捲到 ⑤ 銀行帳戶）
private struct WealthPageRibbonView: View {
    let ribbon: WealthPageRibbon
    let pal: TripBoardPalette
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ribbon.accessibilityText)
        .accessibilityHint("點兩下捲到銀行帳戶")
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            if ribbon.segments.count >= 2 {
                MoneyShareRibbon(segments: ribbon.segments)
            }
            ChipFlowLayout(spacing: 12) {
                ForEach(ribbon.legend) { l in
                    MoneyLegendItem(mark: .swatch, color: l.theme.midColor, text: l.text, pal: pal)
                }
            }
        }
    }
}

/// 四格：一列兩格；只有一格（沒有卡）或字放到 xxLarge 以上一列一格
private struct WealthPageTiles: View {
    let tiles: [WealthPageTile]
    let pal: TripBoardPalette
    let onTile: (WealthPageAnchor) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if tiles.count == 1 || typeSize >= .xxLarge {
            VStack(spacing: 8) {
                ForEach(tiles) { t in
                    tile(t)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            MoneyTileGrid(tiles: tiles.map { AnyView(tile($0)) })
        }
    }

    private func tile(_ t: WealthPageTile) -> some View {
        let target = t.target
        let action: () -> Void = { onTile(target) }
        return MoneyTile(icon: t.icon, tint: t.tint, label: t.label, value: t.value, valueTone: t.valueTone,
                         detail: t.detail, accent: t.accent, accentTone: t.accentTone, action: action,
                         actionHint: hint(target), watermark: t.icon, pal: pal)
    }

    private func hint(_ a: WealthPageAnchor) -> String {
        switch a {
        case .upcoming: return "點兩下捲到接下來 30 天"
        case .cards: return "點兩下捲到信用卡"
        case .banks: return "點兩下捲到銀行帳戶"
        }
    }
}

/// 新手：三顆大按鈕〔＋ 薪轉帳戶〕〔＋ 信用卡〕〔＋ 保單〕（放不下一列就疊起來）
private struct WealthPageStarters: View {
    let pal: TripBoardPalette
    let onStarter: (WealthAccountKind) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                buttons
            }
            VStack(spacing: 8) {
                buttons
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        starter("薪轉帳戶", kind: .bank)
        starter("信用卡", kind: .card)
        starter("保單", kind: .policy)
    }

    private func starter(_ title: String, kind: WealthAccountKind) -> some View {
        Button {
            onStarter(kind)
        } label: {
            Text("＋ " + title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MoneyTone.good.color(pal))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .modifier(TripBoardCellChrome(pal: pal))
                .contentShape(Rectangle())
        }
        .buttonStyle(MoneyPressStyle())
        .accessibilityLabel("新增" + title)
    }
}

// MARK: - ③ 接下來 30 天・各帳戶夠不夠扣

/// ③ 接下來 30 天・各帳戶夠不夠扣（照帳戶回答「錢夠不夠扣」；理財總覽照日期列「要繳什麼」）
struct WealthPageUpcomingSection: View {
    let data: WealthPageUpcoming
    /// 點一列：那個帳戶的銀行頁、捲到「接下來」
    let onRow: (UUID) -> Void
    /// 「看 6 件 ›」
    let onAll: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "接下來 30 天・各帳戶夠不夠扣", trailing: data.trailing)
            card
                .modifier(FinanceCardChrome())
        }
    }

    private var card: some View {
        let pal = TripBoardPalette(scheme)
        return VStack(spacing: 0) {
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 56)
                }
                row(r, pal: pal)
            }
            Divider().padding(.leading, 14)
            allButton(pal)
        }
    }

    private func row(_ r: WealthPageUpcomingRow, pal: TripBoardPalette) -> some View {
        Button {
            onRow(r.id)
        } label: {
            WealthPageUpcomingLine(row: r, pal: pal)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.accessibilityText)
        .accessibilityHint("點兩下打開這個帳戶的接下來")
        .accessibilityAddTraits(.isButton)
    }

    private func allButton(_ pal: TripBoardPalette) -> some View {
        Button(action: onAll) {
            Text("看 " + data.trailing + " ›")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pal.hint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("看接下來 30 天全部 " + data.trailing)
    }
}

/// ③ 一列：[drop] 薪轉（台新）　最低 約 7.6萬　✓ 夠扣／第二行最大的兩件
private struct WealthPageUpcomingLine: View {
    let row: WealthPageUpcomingRow
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TripBoardIconBadge(icon: "drop.fill", colors: pal.badge(.blue), diameter: 30, dark: pal.dark)
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 6) {
                        name
                        Spacer(minLength: 6)
                        status
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        name
                        status
                    }
                }
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 「薪轉」粗體＋灰色「（台新）」
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(row.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
            if let b = row.bank {
                Text(b)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// 「最低 約 7.6萬」＋膠囊「✓ 夠扣」「差 23,940」
    private var status: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(row.lowest)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            FinanceMiniTag(text: row.badge, color: row.badgeTone.color(pal))
        }
        .fixedSize()
    }
}

/// 「看 6 件」：全部帳戶的接下來 30 天照日期排（日期塊＋一句＋金額＋扣完剩多少；變負的整列 warn）
struct WealthPageUpcomingSheet: View {
    let items: [WealthPageUpcomingItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("接下來 30 天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            Text("接下來 30 天沒有會動到存摺的事。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .modifier(FinanceCardChrome())
        } else {
            list
                .modifier(FinanceCardChrome())
        }
    }

    private var list: some View {
        let pal = TripBoardPalette(scheme)
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 {
                    Divider().padding(.leading, 76)
                }
                row(item, pal: pal)
            }
        }
    }

    private func row(_ item: WealthPageUpcomingItem, pal: TripBoardPalette) -> some View {
        let warn = MoneyTone.warn.color(pal)
        let tags: [FinanceRowTag] = item.negative ? [FinanceRowTag(text: "不夠扣", color: warn)] : []
        return FinanceLedgerRow(dayText: item.day, monthText: item.month, glyph: item.glyph,
                                markColor: item.negative ? warn : markColor(item.mark),
                                title: item.title, detail: item.detail, amountText: item.amount, tags: tags,
                                accessibilityText: item.accessibilityText)
    }

    /// 色圓：入帳綠、卡費橘（主題 72）、股票紫（主題 75）、其他藍（主題 71）
    private func markColor(_ m: WealthPageUpcomingItem.Mark) -> Color {
        switch m {
        case .income: return Color(tb: 0x1F9D57)
        case .card: return Color(tb: 0xD9601F)
        case .stock: return Color(tb: 0x6B44E0)
        case .other: return Color(tb: 0x2F6FD6)
        }
    }
}

// MARK: - ⋯ 的兩張說明、⑨ 頁尾

/// ⋯「這頁的數字怎麼算」「iCloud 與家人共享說明」
struct WealthPageInfoSheet: View {
    let topic: WealthPageInfoTopic

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, p in
                        Text(p)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .modifier(FinanceCardChrome())
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// ⑨ 頁尾灰字（一直在；匯率超過 3 天沒更新，最後那句琥珀色）
struct WealthPageFooterView: View {
    let line: FinanceLine

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        FinanceLineText.text(line, pal: TripBoardPalette(scheme))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
