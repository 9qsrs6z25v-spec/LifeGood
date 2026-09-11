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
        self.leading = leading
        self.accessory = accessory
    }

    var body: some View {
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
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
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

// MARK: - 膠囊橫向捲軸

/// 標籤列。多到放不下時自己左右捲，不會把標題擠掉
struct ItemChipBar: View {
    let chips: [ItemChip]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    if let label = chip.leadingLabel, !label.isEmpty {
                        HStack(spacing: 3) {
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                            chipBody(chip)
                        }
                    } else {
                        chipBody(chip)
                    }
                }
            }
            // 膠囊本身可能有點按行為；留一點垂直空間避免描邊被裁掉
            .padding(.vertical, 1)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(isOn ? color : Color.secondary.opacity(0.45))
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
