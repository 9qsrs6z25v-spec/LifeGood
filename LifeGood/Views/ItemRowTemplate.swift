import SwiftUI

// MARK: - 通用項目列模板（v25.354）
//
// 從兼任職務「重大決議」列收斂而成的列式項目模板，三個組成部分：
//   1. 膠囊橫向捲軸（ItemChipBar）：標籤多到擠爆標題時自己左右捲，不壓縮標題
//   2. 標題與預覽（標題完整換行、預覽限行數）
//   3. 摺疊子項目（ItemDisclosure）：預設收合成一顆計數膠囊，
//      展開列出子項目標題，再點一次在原地展開看內文
//
// 各區域需要的額外元素用「插槽」補：
//   • leading   ：勾選框、日期塊、名次徽章……（ItemCheckbox / ItemDateBadge 可直接用）
//   • accessory ：右側的分數、金額、選單按鈕
//   • progress  ：標題下方的進度條（ItemProgress）
//   • extra     ：其他自訂內容（地圖、迷你圖表……）
//
// ── 為什麼用 AnyView 當插槽 ──
// 本專案有過 SwiftUI 型別深度爆棧的事故（見 SideRoleView.sectionBox 的註解），
// 巢狀泛型插槽會讓每一層呼叫端的型別再長一截。這裡刻意只留兩個泛型
// （Leading / Accessory）並提供 EmptyView 版的便利初始化，其餘插槽走 AnyView：
// 列式項目數量有限，抹型別的成本遠低於編譯期爆掉的風險。
//
// ── 用法 ──
//   ItemRow(
//       chips: [ItemChip(text: "#003", color: .purple), ItemChip(text: "9/11", color: .indigo)],
//       title: "廢水系統改善決議",
//       preview: "本次確認改善方案與預算……",
//       disclosures: refs.map { ItemDisclosure(id: $0.id.uuidString, title: $0.title, body: $0.content) },
//       onTap: { open(item) }
//   )
// 需要勾選框與進度條時：
//   ItemRow(leading: { ItemCheckbox(isOn: task.isDone) { toggle() } },
//           chips: chips, title: task.title,
//           progress: ItemProgress(value: 0.4, color: .orange, label: "4 / 10"),
//           accessory: { Text("120").font(.headline) })

// MARK: - 資料型別

/// 膠囊。可點（篩選）時給 onTap；active 代表目前正被用來篩選，會加深並帶 ✕
struct ItemChip: Identifiable {
    let id: String
    var text: String
    var color: Color
    /// 膠囊前面的小字（例：「發起」）
    var leadingLabel: String?
    var icon: String?
    var isActive: Bool
    var onTap: (() -> Void)?

    init(id: String? = nil, text: String, color: Color = .secondary,
         leadingLabel: String? = nil, icon: String? = nil,
         isActive: Bool = false, onTap: (() -> Void)? = nil) {
        self.id = id ?? "\(leadingLabel ?? "")-\(text)"
        self.text = text
        self.color = color
        self.leadingLabel = leadingLabel
        self.icon = icon
        self.isActive = isActive
        self.onTap = onTap
    }
}

/// 摺疊子項目。body 是展開後看到的內文；action 是展開後右下的跳轉動作
struct ItemDisclosure: Identifiable {
    let id: String
    var badge: String?
    var title: String
    var meta: String?
    var body: String
    var actionLabel: String?
    var action: (() -> Void)?

    init(id: String, badge: String? = nil, title: String, meta: String? = nil,
         body: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.id = id; self.badge = badge; self.title = title
        self.meta = meta; self.body = body
        self.actionLabel = actionLabel; self.action = action
    }
}

/// 標題下方的進度條
struct ItemProgress {
    var value: Double          // 0...1
    var color: Color
    var label: String?

    init(value: Double, color: Color = .green, label: String? = nil) {
        self.value = min(max(value, 0), 1); self.color = color; self.label = label
    }
}

// MARK: - 主體

struct ItemRow<Leading: View, Accessory: View>: View {

    // 內容
    var chips: [ItemChip] = []
    var title: String
    var titleIsMuted: Bool = false
    var titleStrikethrough: Bool = false
    /// 點標題的動作（例：以這個人篩選）。有值時標題右邊會留一個可點的熱區
    var titleTap: (() -> Void)?
    /// 標題目前正被拿來篩選：加底色並附 ✕
    var titleIsFiltering: Bool = false
    var preview: String?
    var previewLineLimit: Int = 3
    var progress: ItemProgress?
    var disclosures: [ItemDisclosure] = []
    /// 摺疊區的標題，例：「參照前案」「子任務」
    var disclosureLabel: String = "子項目"
    var disclosureColor: Color = .indigo
    var extra: AnyView?
    /// [v25.360] 由外部強制展開子項目清單（搜尋跳轉時用）。
    /// 列自己的展開狀態仍然有效，兩者取聯集。
    var forceOpen: Bool = false
    /// [v25.360] 要標亮並自動展開內文的子項目 id（搜尋命中的那一筆）
    var highlightId: String?
    var onTap: (() -> Void)?

    // MARK: 版面（v25.502）

    /// 標題橫向貫穿。
    ///
    /// 預設 false，所有既有畫面維持原樣。
    ///
    /// 為什麼要有這個模式：行程時間軸那一列，左邊是時間欄（52pt）加打卡圈
    /// 加編號圈，右邊是拖曳把手與「…」，中間留給標題的只剩 207pt——
    /// 不到畫面寬度的一半。「福岡 Anpanman Kodomo Museum in Mall」因此折成
    /// 三行。一站的名字是這一列的主角，主角分到的寬度比配角少，
    /// 怎麼排都不會好看。
    ///
    /// 開啟後：指示器、標題、右側動作自成**一列**，標題吃掉整條剩餘寬度；
    /// 其餘內容（膠囊、地址、附註）排在底下，縮排 bodyInset 對齊標題的起點。
    /// 順便把膠囊從標題**上面**移到**下面**——名字該先被讀到。
    var spansTitle: Bool = false

    /// spansTitle 模式下，標題底下那一塊往右縮排多少（＝指示器寬度 ＋ 間距）。
    /// 呼叫端自己算，因為只有它知道自己的指示器多寬；也因此務必給**固定寬度**，
    /// 不然有打卡圈與沒打卡圈的兩列會對不齊，那比不縮排還難看。
    var bodyInset: CGFloat = 0

    /// 列底下的淡色分隔線。
    ///
    /// 時間軸上一站接一站，中間只有一條很淡的交通資訊，區塊與區塊之間
    /// 沒有邊界——眼睛要自己判斷哪幾行屬於同一站。一條髮絲線就夠了。
    var showsSeparator: Bool = false
    /// 分隔線從左邊再縮排多少（0＝切齊內容左緣，像 iOS 原生清單）
    var separatorInset: CGFloat = 0

    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var accessory: () -> Accessory

    /// 哪些子項目展開了內文（列自己管，呼叫端不用傳狀態進來）
    @State private var openBodies: Set<String> = []
    @State private var listOpen = false

    /// 明確寫出初始化，不靠合成的 memberwise init——
    /// 上面有 private 的 @State，合成版會跟著變成 private，跨檔案叫不到。
    init(chips: [ItemChip] = [], title: String, titleIsMuted: Bool = false,
         titleStrikethrough: Bool = false, titleTap: (() -> Void)? = nil,
         titleIsFiltering: Bool = false,
         preview: String? = nil, previewLineLimit: Int = 3,
         progress: ItemProgress? = nil, disclosures: [ItemDisclosure] = [],
         disclosureLabel: String = "子項目", disclosureColor: Color = .indigo,
         extra: AnyView? = nil, forceOpen: Bool = false, highlightId: String? = nil,
         onTap: (() -> Void)? = nil,
         spansTitle: Bool = false, bodyInset: CGFloat = 0,
         showsSeparator: Bool = false, separatorInset: CGFloat = 0,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.chips = chips
        self.title = title
        self.titleIsMuted = titleIsMuted
        self.titleStrikethrough = titleStrikethrough
        self.titleTap = titleTap
        self.titleIsFiltering = titleIsFiltering
        self.preview = preview
        self.previewLineLimit = previewLineLimit
        self.progress = progress
        self.disclosures = disclosures
        self.disclosureLabel = disclosureLabel
        self.disclosureColor = disclosureColor
        self.extra = extra
        self.forceOpen = forceOpen
        self.highlightId = highlightId
        self.onTap = onTap
        self.spansTitle = spansTitle
        self.bodyInset = bodyInset
        self.showsSeparator = showsSeparator
        self.separatorInset = separatorInset
        self.leading = leading
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 0) {
            if spansTitle { spanningLayout } else { inlineLayout }
            if showsSeparator {
                Rectangle()
                    .fill(Color(.separator).opacity(0.55))
                    .frame(height: 0.5)
                    .padding(.leading, 14 + separatorInset)
            }
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    /// 原本的樣子：左指示器、中間一疊內容、右動作。
    private var inlineLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            leading()
            VStack(alignment: .leading, spacing: 5) {
                if !chips.isEmpty { ItemChipBar(chips: chips) }
                titleView
                if let p = progress { progressBar(p) }
                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(previewLineLimit)
                }
                if let extra { extra }
                if !disclosures.isEmpty { disclosureSection }
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// [v25.502] 標題貫穿：名字自成一列，其餘縮排在底下。
    private var spanningLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                leading()
                // 不用 Spacer 把右邊的動作推過去，改讓標題自己吃掉剩餘寬度。
                //
                // HStack 的 spacing 是**每一對相鄰元素之間**都算一次，所以
                // 夾一個 Spacer(minLength: 0) 進來不是「零寬度」——它是
                // 10pt ＋ 0 ＋ 10pt，白白從標題身上拿走 20pt。
                // 這一列能給標題的本來就只有兩百出頭，20pt 是一成。
                titleView
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory()
            }
            // 順序跟 inline 版不一樣，是刻意的：
            //
            // 1. 膠囊在標題**下面**。排在名字前面的話，一列最先被讀到的是
            //    「第 5 天」而不是地名——附註不該站在身分前面。
            // 2. 地址緊跟著名字。「這是哪裡」是名字的下一個問題，
            //    中間不該插著狀態膠囊。
            // 3. 狀態膠囊（停留多久、指定抵達）與附註膠囊（天氣、電話）
            //    併在一起收尾。同一種形狀的東西擠在同一區，掃過去是一次。
            VStack(alignment: .leading, spacing: 5) {
                if let p = progress { progressBar(p) }
                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(previewLineLimit)
                }
                if !chips.isEmpty { ItemChipBar(chips: chips) }
                if let extra { extra }
                if !disclosures.isEmpty { disclosureSection }
            }
            .padding(.leading, bodyInset)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    // MARK: 標題

    @ViewBuilder
    private var titleView: some View {
        let text = Text(title.isEmpty ? "（未填標題）" : title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(titleIsMuted ? Color.secondary : Color.primary)
            .strikethrough(titleStrikethrough, color: .secondary)
        if let titleTap {
            Button(action: titleTap) {
                HStack(spacing: 4) {
                    text.fixedSize(horizontal: false, vertical: true)
                    if titleIsFiltering {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(.indigo)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            text.fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 進度條

    private func progressBar(_ p: ItemProgress) -> some View {
        HStack(spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(LinearGradient(colors: [p.color, p.color.opacity(0.65)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * p.value))
                }
            }
            .frame(height: 5)
            if let label = p.label {
                Text(label)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(p.color)
            }
        }
    }

    // MARK: 摺疊子項目

    private var disclosureSection: some View {
        // 自己展開的，或外部（搜尋跳轉）要求展開的
        let isOpen = listOpen || forceOpen
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { listOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(disclosureLabel) \(disclosures.count) 項")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(disclosureColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(disclosureColor.opacity(0.22), lineWidth: 0.6))
                .foregroundStyle(disclosureColor)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(disclosures) { d in disclosureLine(d) }
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func disclosureLine(_ d: ItemDisclosure) -> some View {
        let isHit = d.id == highlightId
        let open = openBodies.contains(d.id) || isHit
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if open { openBodies.remove(d.id) } else { openBodies.insert(d.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(disclosureColor.opacity(0.7))
                        .frame(width: 10)
                    if let badge = d.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(disclosureColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(disclosureColor)
                    }
                    Text(d.title.isEmpty ? "（未填標題）" : d.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(open ? 3 : 1)
                        .multilineTextAlignment(.leading)
                    if let meta = d.meta, !meta.isEmpty {
                        Text(meta).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, isHit ? 5 : 0)
                .padding(.vertical, isHit ? 3 : 0)
                .background(isHit ? disclosureColor.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                Text(d.body.isEmpty ? "（未填內容）" : d.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                if let label = d.actionLabel, let action = d.action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(label).font(.system(size: 10, weight: .bold))
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(disclosureColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - 便利初始化（沒有 leading／accessory 時不用寫空的 closure）

extension ItemRow where Leading == EmptyView, Accessory == EmptyView {
    init(chips: [ItemChip] = [], title: String, titleIsMuted: Bool = false,
         titleStrikethrough: Bool = false, titleTap: (() -> Void)? = nil,
         titleIsFiltering: Bool = false,
         preview: String? = nil, previewLineLimit: Int = 3,
         progress: ItemProgress? = nil, disclosures: [ItemDisclosure] = [],
         disclosureLabel: String = "子項目", disclosureColor: Color = .indigo,
         extra: AnyView? = nil, forceOpen: Bool = false, highlightId: String? = nil,
         onTap: (() -> Void)? = nil) {
        self.init(chips: chips, title: title, titleIsMuted: titleIsMuted,
                  titleStrikethrough: titleStrikethrough, titleTap: titleTap,
                  titleIsFiltering: titleIsFiltering, preview: preview,
                  previewLineLimit: previewLineLimit, progress: progress,
                  disclosures: disclosures, disclosureLabel: disclosureLabel,
                  disclosureColor: disclosureColor, extra: extra,
                  forceOpen: forceOpen, highlightId: highlightId, onTap: onTap,
                  leading: { EmptyView() }, accessory: { EmptyView() })
    }
}

extension ItemRow where Leading == EmptyView {
    init(chips: [ItemChip] = [], title: String, titleIsMuted: Bool = false,
         titleStrikethrough: Bool = false, titleTap: (() -> Void)? = nil,
         titleIsFiltering: Bool = false,
         preview: String? = nil, previewLineLimit: Int = 3,
         progress: ItemProgress? = nil, disclosures: [ItemDisclosure] = [],
         disclosureLabel: String = "子項目", disclosureColor: Color = .indigo,
         extra: AnyView? = nil, forceOpen: Bool = false, highlightId: String? = nil,
         onTap: (() -> Void)? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(chips: chips, title: title, titleIsMuted: titleIsMuted,
                  titleStrikethrough: titleStrikethrough, titleTap: titleTap,
                  titleIsFiltering: titleIsFiltering, preview: preview,
                  previewLineLimit: previewLineLimit, progress: progress,
                  disclosures: disclosures, disclosureLabel: disclosureLabel,
                  disclosureColor: disclosureColor, extra: extra,
                  forceOpen: forceOpen, highlightId: highlightId, onTap: onTap,
                  leading: { EmptyView() }, accessory: accessory)
    }
}

extension ItemRow where Accessory == EmptyView {
    init(chips: [ItemChip] = [], title: String, titleIsMuted: Bool = false,
         titleStrikethrough: Bool = false, titleTap: (() -> Void)? = nil,
         titleIsFiltering: Bool = false,
         preview: String? = nil, previewLineLimit: Int = 3,
         progress: ItemProgress? = nil, disclosures: [ItemDisclosure] = [],
         disclosureLabel: String = "子項目", disclosureColor: Color = .indigo,
         extra: AnyView? = nil, forceOpen: Bool = false, highlightId: String? = nil,
         onTap: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading) {
        self.init(chips: chips, title: title, titleIsMuted: titleIsMuted,
                  titleStrikethrough: titleStrikethrough, titleTap: titleTap,
                  titleIsFiltering: titleIsFiltering, preview: preview,
                  previewLineLimit: previewLineLimit, progress: progress,
                  disclosures: disclosures, disclosureLabel: disclosureLabel,
                  disclosureColor: disclosureColor, extra: extra,
                  forceOpen: forceOpen, highlightId: highlightId, onTap: onTap,
                  leading: leading, accessory: { EmptyView() })
    }
}

// MARK: - 出圖模式

private struct ItemRowChipsWrapKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// [v25.371] 把膠囊列從「橫向捲動」改成「自動換行」。
    /// ImageRenderer 出的是靜態圖，捲不動＝捲出畫面的膠囊等於整個消失
    /// （出圖的版面有固定寬度，ScrollView 只會把超出的部分裁掉）。
    /// 匯出前在最外層掛 `.environment(\.itemRowChipsWrap, true)`，
    /// 底下所有 ItemRow 自動改用換行排版，呼叫端一行都不用改。
    var itemRowChipsWrap: Bool {
        get { self[ItemRowChipsWrapKey.self] }
        set { self[ItemRowChipsWrapKey.self] = newValue }
    }
}

// MARK: - 膠囊橫向捲軸

/// 標籤列。多到放不下時自己左右捲，不會把標題擠掉。
/// 出圖模式（itemRowChipsWrap）下改成換行，避免捲出畫面的膠囊在圖片裡不見。
struct ItemChipBar: View {
    let chips: [ItemChip]
    @Environment(\.itemRowChipsWrap) private var wrapChips

    var body: some View {
        if wrapChips {
            ChipFlowLayout(spacing: 6) {
                ForEach(chips) { chip in chipEntry(chip) }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in chipEntry(chip) }
                }
                // 膠囊本身可能有點按行為；留一點垂直空間避免描邊被裁掉
                .padding(.vertical, 1)
            }
            .scrollEdgeFade()
        }
    }

    @ViewBuilder
    private func chipEntry(_ chip: ItemChip) -> some View {
        if let label = chip.leadingLabel, !label.isEmpty {
            HStack(spacing: 3) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                chipBody(chip)
            }
        } else {
            chipBody(chip)
        }
    }

    @ViewBuilder
    private func chipBody(_ chip: ItemChip) -> some View {
        if let onTap = chip.onTap {
            Button(action: onTap) { chipLabel(chip) }
                .buttonStyle(.borderless)
        } else {
            chipLabel(chip)
        }
    }

    private func chipLabel(_ chip: ItemChip) -> some View {
        HStack(spacing: 3) {
            if let icon = chip.icon {
                Image(systemName: icon).font(.system(size: 8, weight: .bold))
            }
            Text(chip.text)
            if chip.isActive {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(chip.color)
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(chip.color.opacity(chip.isActive ? 0.25 : 0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(chip.color.opacity(chip.isActive ? 0.5 : 0.25), lineWidth: 0.6))
    }
}

// MARK: - 常用的 leading 元件

/// 勾選框。放在 ItemRow 的 leading 插槽
struct ItemCheckbox: View {
    let isOn: Bool
    var color: Color = .green
    /// [v25.371] 未勾選時的圈圈顏色。預設淡灰；有些區域（部屬任務）習慣用章節色，
    /// 沒有這個參數就只能在呼叫端自己重刻一顆按鈕。
    var offColor: Color = Color.secondary.opacity(0.45)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(isOn ? color : offColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
    }
}

/// 36pt 漸層圖示圓。部屬總覽那套列左側的標準樣式：
/// 給 action 就是可點的（勾選／切換狀態），不給就是純圖示。
struct ItemIconDisc: View {
    let icon: String
    var color: Color = .secondary
    var size: CGFloat = 36
    var iconSize: CGFloat = 15
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { disc }
                .buttonStyle(.plain)
        } else {
            disc
        }
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.18), radius: 5, x: 0, y: 2)
            Circle()
                .stroke(color.opacity(0.22), lineWidth: 1)
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
        }
        .contentShape(Circle())
    }
}

/// 日期塊（大字日、小字月）。放在 ItemRow 的 leading 插槽
struct ItemDateBadge: View {
    let date: Date
    var color: Color = .secondary

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月"; return f
    }()

    var body: some View {
        VStack(spacing: 1) {
            Text(Self.dayFmt.string(from: date))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(Self.monthFmt.string(from: date))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(width: 34)
    }
}

// MARK: - 橫向捲軸的隱沒感（v25.415 / 抽成共用 v25.416）

/// 橫向捲軸兩側的淡出遮罩。
///
/// 內容超出寬度時，SwiftUI 預設是硬生生切一刀，看起來像版面壞掉；
/// 淡出之後就變成「捲進去了」。**只淡「那一側真的還有東西」的那一邊**——
/// 已經捲到底還淡，反而會看起來像沒對齊。
struct ScrollEdgeFade: ViewModifier {
    /// 淡出的寬度。太窄看不出來、太寬會把整個項目吃掉；18pt 大約是一個字的寬度。
    var width: CGFloat = 18

    @State private var edges = Edges()

    struct Edges: Equatable {
        var leading = false
        var trailing = false
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Edges.self) { geo in
                Edges(
                    leading: geo.contentOffset.x > 1,
                    trailing: geo.contentOffset.x + geo.containerSize.width
                        < geo.contentSize.width - 1)
            } action: { _, new in
                // 捲動過程中值不變就不要一直觸發動畫
                guard new != edges else { return }
                withAnimation(.easeOut(duration: 0.18)) { edges = new }
            }
            .mask(mask)
    }

    /// 用三段固定寬度拼出來而不是 GeometryReader 讀寬度算比例：
    /// 這個修飾器會用在長清單的每一列上，每列塞一個 GeometryReader 不划算；
    /// 而且容器有多寬跟「隱沒感該有多長」本來就沒有關係。
    private var mask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: edges.leading ? width : 0)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: edges.trailing ? width : 0)
        }
    }
}

extension View {
    /// 橫向捲軸兩側淡出，讓超出畫面的內容看起來是捲進去而不是被切掉。
    /// 只能用在 ScrollView 上（靠捲動幾何判斷哪一側還有內容）。
    func scrollEdgeFade(width: CGFloat = 18) -> some View {
        modifier(ScrollEdgeFade(width: width))
    }

    /// [v25.481] 把直向捲動內容的寬度釘死成容器寬度：這一頁只能上下捲。
    ///
    /// 為什麼需要：直向 ScrollView 問內容「你理想多寬」的時候，**橫向捲軸會老實
    /// 回答它整條內容的寬度**——時間軸上的膠囊列、照片條、摘要卡的日期色帶都是
    /// 橫向捲軸，七天的日期膠囊排開就是五、六百點。那個數字會變成外層捲動區域
    /// 的內容寬度，於是整頁多出一兩百點的空白、可以左右拖，但實際排版仍然是
    /// 螢幕寬（卡片量起來一樣是 螢幕寬 − 32），拖出去的地方什麼都沒有。
    ///
    /// v25.474 修掉了同一個毛病的另一個來源（換行膠囊容器被問到理想寬度時回報
    /// 「全部排成一列」的總寬）。那次是治標的一個洞；橫向捲軸是天生如此，
    /// 沒辦法一個一個改，所以改成在容器這一端把寬度釘死。
    ///
    /// 釘死之後萬一真的有東西比螢幕寬，它會被切掉而不是變成可以拖——
    /// 這是刻意的：那種情況是版面有問題，應該修版面，不是讓整頁跟著歪。
    func scrollVerticalOnly() -> some View {
        containerRelativeFrame(.horizontal, alignment: .leading)
    }
}

// MARK: - 細進度條（v25.422）

/// 細進度條。版型取自底部導覽上方那條匯出進度條，抽出來讓別的地方也能用。
///
/// 用在「使用者按了之後要等，但畫面上看不出在等什麼」的地方——
/// 最典型的就是從 iCloud 相簿選照片：原圖還在雲端時要先下載，
/// 沒有任何提示的話看起來就像沒選到。
struct ThinProgressBar: View {
    let label: String
    /// 0...1；nil＝不知道總量，畫成來回跑的不確定進度
    var fraction: Double?
    var tint: Color = Color(red: 0.16, green: 0.74, blue: 0.50)
    var icon: String = "arrow.down.circle.fill"

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: icon)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.14))
                            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.6))
                        Capsule()
                            .fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
                            .shadow(color: tint.opacity(0.40), radius: 3)
                            .animation(.linear(duration: 0.2), value: fraction)
                    }
                }
                .frame(height: 3)
            } else {
                // 不知道總量時用系統的不確定進度條，不要自己假裝在跑
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(height: 3)
            }
        }
    }
}
