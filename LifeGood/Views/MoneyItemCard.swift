import SwiftUI
import CoreLocation

// MARK: - 收支項目的卡片（v25.524）
//
// 每一筆收支一張卡：左邊卡面（MoneyArt.swift 的 MoneyPanel：照片／衛星空照／分類插畫），
// 右邊名稱＋金額、分類色點＋分類＋地點或備註、一排玻璃膠囊（付款卡片、同行的人、
// 綁定的旅程…），底色是很淡的分類色。綁了旅程的支出，卡片底下多一條那座城市的天際線
// （行程卡的 TripCardSkyline）。
//
// 緊湊模式（使用者：「加緊湊也可以」）：左邊換成小方塊、一筆一行半，給一次要滑很多筆的時候用。
// 三頁（變動支出、收入、固定支出）共用同一個開關（MoneyItemCard.compactKey）。
//
// 這個檔案只管「長什麼樣子」；一筆支出／收入要變成什麼字，在下面的 MoneyItem 工廠函式裡，
// 點擊、左滑、刪除還是各頁自己管（行為跟原本一樣）。

private extension String {
    var moneyTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - 資料

/// 卡片上的一顆膠囊
struct MoneyItemChip: Hashable, Identifiable {
    let icon: String
    let text: String
    var tone: MoneyTone = .neutral
    var id: String { icon + "|" + text }
}

/// 繳費進度（貸款、儲蓄險）
struct MoneyItemProgress: Equatable {
    let fraction: Double
    let leading: String
    let trailing: String?
}

/// 綁了旅程的支出：卡片底下那條天際線
struct MoneyItemSkyline: Equatable {
    let landmarks: [TripLandmark]
    let seed: Int
}

struct MoneyItem: Identifiable, Equatable {
    enum AmountStyle: Equatable { case expense, income }

    let id: UUID
    var theme: MoneyArtTheme
    var seed: Int
    var title: String
    var amount: String
    var amountStyle: AmountStyle = .expense
    /// 金額後面的小字（/月）
    var unit: String? = nil
    var category: String
    var detail: String? = nil
    /// 卡面左上的小膠囊（時間、日期、週期）
    var badge: String? = nil
    var chips: [MoneyItemChip] = []
    var photoURL: URL? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// 地址切出來的城市（手寫城市名用）
    var place: TripPlaceName.Place? = nil
    /// 訂閱服務：卡面上的大字母
    var monogram: String? = nil
    var skyline: MoneyItemSkyline? = nil
    var progress: MoneyItemProgress? = nil
    /// 已停止的固定支出、已結束的固定薪水：整張淡一點，但還在清單裡
    var dimmed: Bool = false

    /// UUID 的雜湊每次開 App 都不一樣；紋理要每次都長一樣，所以用位元組算
    static func seed(_ id: UUID) -> Int {
        let u = id.uuid
        return Int(u.0) &* 31 &+ Int(u.5) &* 17 &+ Int(u.10) &* 7 &+ Int(u.15)
    }
}

// MARK: - 卡片

struct MoneyItemCard: View {
    let item: MoneyItem
    var compact: Bool = false

    /// 緊湊模式的開關（變動支出、收入、固定支出三頁共用）
    static let compactKey = "money_items_compact"
    /// 卡面的寬
    static let panelWidth: CGFloat = 108

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                fullBody
            }
        }
        .opacity(item.dimmed ? 0.58 : 1)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private var pal: TripBoardPalette { TripBoardPalette(scheme) }

    private var a11y: String {
        var parts = [item.title, item.category, item.amount + (item.unit ?? "")]
        if let d = item.detail, !d.isEmpty { parts.append(d) }
        if let b = item.badge { parts.append(b) }
        parts += item.chips.map(\.text)
        if let p = item.progress {
            parts.append(p.leading)
            if let t = p.trailing { parts.append(t) }
        }
        return parts.joined(separator: "，")
    }

    // MARK: 一般

    private var fullBody: some View {
        let w = Self.panelWidth
        let hasSky = item.skyline != nil
        return VStack(alignment: .leading, spacing: 0) {
            titleRow
            metaRow
                .padding(.top, 3)
            if !item.chips.isEmpty {
                chipRow
                    .padding(.top, 8)
            }
            if let p = item.progress {
                progressRow(p)
                    .padding(.top, 9)
            }
        }
        .padding(.leading, w + 8)
        .padding(.trailing, 13)
        .padding(.top, 12)
        .padding(.bottom, hasSky ? 24 : 12)
        .frame(maxWidth: .infinity, minHeight: hasSky ? 114 : 106, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            if let sky = item.skyline {
                TripCardSkyline(color: item.theme.tintColor, seed: sky.seed, landmarks: sky.landmarks,
                                planeTrail: true, ink: scheme == .dark ? .dayDark : .boardDay,
                                glow: 0, dark: scheme == .dark)
                    .equatable()
                    .frame(height: 18)
                    .padding(.leading, w + 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(alignment: .leading) {
            MoneyPanel(theme: item.theme, seed: item.seed, monogram: item.monogram, badge: item.badge,
                       photoURL: item.photoURL, latitude: item.latitude, longitude: item.longitude,
                       place: item.place, width: w)
                .frame(width: w)
                .clipShape(MoneyPanelShape())
        }
        .background { cardBase }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .shadow(color: scheme == .dark ? Color.black.opacity(0.32) : Color(tb: 0x1E3A6E, 0.08),
                radius: 6, x: 0, y: 2)
    }

    /// 卡底：系統的卡片底色＋上面一層很淡的分類色（像行程卡的天空）
    private var cardBase: some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            LinearGradient(colors: [item.theme.tintColor.opacity(scheme == .dark ? 0.16 : 0.10),
                                    item.theme.tintColor.opacity(0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.75))
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MarqueeText(item.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            amountView
        }
    }

    private var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(item.amount)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(item.amountStyle == .income ? MoneyTone.good.color(pal) : Color.primary)
            if let unit = item.unit {
                Text(unit)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .layoutPriority(1)
    }

    private var metaRow: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.theme.tintColor)
                .frame(width: 6, height: 6)
            Text(item.category)
                .font(.caption.weight(.bold))
                .foregroundStyle(item.theme.ink(scheme))
                .lineLimit(1)
                .fixedSize()
            if let d = item.detail, !d.isEmpty {
                Text("・" + d)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// 膠囊一列放不下就少放幾顆（不換行、不捲動）
    private var chipRow: some View {
        ViewThatFits(in: .horizontal) {
            chipLine(item.chips)
            chipLine(Array(item.chips.prefix(2)))
            chipLine(Array(item.chips.prefix(1)))
            if let first = item.chips.first {
                MoneyItemChipView(chip: first)
            }
        }
    }

    private func chipLine(_ chips: [MoneyItemChip]) -> some View {
        HStack(spacing: 5) {
            ForEach(chips) { c in
                MoneyItemChipView(chip: c)
                    .fixedSize()
            }
        }
        .fixedSize()
    }

    private func progressRow(_ p: MoneyItemProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.progressTrack)
                    Capsule()
                        .fill(LinearGradient(colors: [item.theme.topColor, item.theme.bottomColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(5, geo.size.width * CGFloat(min(1, max(0, p.fraction)))))
                }
            }
            .frame(height: 5)
            HStack {
                Text(p.leading)
                Spacer(minLength: 6)
                if let t = p.trailing { Text(t) }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    // MARK: 緊湊

    private var compactBody: some View {
        HStack(spacing: 10) {
            MoneyThumb(theme: item.theme, seed: item.seed, photoURL: item.photoURL)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                metaRow
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                amountView
                if let b = item.badge {
                    Text(b)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background { cardBase }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .shadow(color: scheme == .dark ? Color.black.opacity(0.28) : Color(tb: 0x1E3A6E, 0.06),
                radius: 4, x: 0, y: 1)
    }
}

/// 卡片上的一顆膠囊
struct MoneyItemChipView: View {
    let chip: MoneyItemChip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chip.icon)
                .font(.system(size: 9, weight: .bold))
            Text(chip.text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(chip.tone == .neutral ? Color.secondary : chip.tone.color(TripBoardPalette(scheme)))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.09), lineWidth: 0.75))
    }
}

/// 三頁右上角的「緊湊／一般」切換鈕
struct MoneyCompactToggle: View {
    @Binding var compact: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { compact.toggle() }
        } label: {
            Image(systemName: compact ? "rectangle.grid.1x2" : "list.bullet")
                .font(.body.weight(.semibold))
        }
        .accessibilityLabel(compact ? "改成一般卡片" : "改成緊湊列表")
    }
}

// MARK: - 標頭

/// 一天一組的日期標頭：日曆的大數字＋月份與星期＋「今天／昨天」，右邊當天幾筆、合計
struct MoneyDayHeader: View {
    let date: Date
    let count: Int
    let total: String
    /// 合計的字色（收入用 .good 的綠）；nil＝一般字色
    var totalTone: MoneyTone? = nil

    @Environment(\.colorScheme) private var scheme

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M 月"
        return f
    }()
    private static let yearMonthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M"
        return f
    }()
    private static let weekFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let thisYear = cal.isDate(date, equalTo: Date(), toGranularity: .year)
        let tag: String? = cal.isDateInToday(date) ? "今天" : (cal.isDateInYesterday(date) ? "昨天" : nil)
        HStack(alignment: .center, spacing: 8) {
            Text(day < 10 ? "0\(day)" : "\(day)")
                .font(.system(.title, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text(thisYear ? Self.monthFmt.string(from: date) : Self.yearMonthFmt.string(from: date))
                Text(Self.weekFmt.string(from: date))
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            if let tag {
                Text(tag)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(tb: 0x2F7FE8), in: Capsule())
            }
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count) 筆・")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(total)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(totalTone.map { $0.color(TripBoardPalette(scheme)) } ?? Color.primary)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .textCase(nil)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

/// 固定支出一個分類一組的標頭：分類插畫的小方塊＋分類名＋幾項，右邊每月合計
struct MoneyGroupHeader: View {
    let theme: MoneyArtTheme
    let title: String
    let count: Int
    let total: String

    var body: some View {
        HStack(spacing: 9) {
            MoneyArtwork(theme: theme, seed: theme.id, layout: .thumb)
                .equatable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(count) 項")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(total)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .textCase(nil)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

/// 頁面上一段的標頭（總覽「本月花在哪裡」「最近交易」、圖表頁）
struct MoneySectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 圖表卡（圖表頁每張圖一張）

/// 圖表頁的一張卡：上方一條插畫橫幅（手寫字 Trends／Spending…），下面標題列與圖。
///
/// 內容用 AnyView 傳進來：圖表本身（Swift Charts）的型別已經很深，這裡再包一層泛型
/// 會讓型別更深（本專案踩過泛型型別太深、demangle 時 stack overflow 的閃退）。
struct MoneyChartCard: View {
    let theme: MoneyArtTheme
    let title: String
    var trailing: String? = nil
    let content: AnyView

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoneyArtwork(theme: theme, seed: theme.id, layout: .banner)
                .equatable()
                .frame(height: 58)
                .overlay(alignment: .leading) {
                    MoneyArtScript(word: theme.word, caps: theme.caps, maxWidth: 240, size: 25)
                        .padding(.leading, 14)
                        .padding(.bottom, 8)
                }
                .clipShape(MoneyBannerShape())
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let trailing {
                    Text(trailing)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.ink(scheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(theme.tintColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(theme.tintColor.opacity(0.25), lineWidth: 0.75))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            content
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                LinearGradient(colors: [theme.tintColor.opacity(scheme == .dark ? 0.12 : 0.06),
                                        theme.tintColor.opacity(0)],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .shadow(color: scheme == .dark ? Color.black.opacity(0.32) : Color(tb: 0x1E3A6E, 0.08),
                radius: 8, x: 0, y: 3)
        .padding(.horizontal)
    }
}

// MARK: - 分類明信片（總覽「本月花在哪裡」）

struct MoneyCategoryPostcard: View {
    let theme: MoneyArtTheme
    let name: String
    let amount: String
    let share: Double
    let count: Int
    /// 比上個月同一段時間（↑20%／↓8%／持平）；上個月那段時間沒花就是 nil
    let change: String?
    let changeTone: MoneyTone

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        let ink = theme.ink(scheme)
        VStack(alignment: .leading, spacing: 0) {
            MoneyArtwork(theme: theme, seed: theme.id, layout: .banner)
                .equatable()
                .frame(height: 74)
                .overlay(alignment: .bottomLeading) {
                    MoneyArtScript(word: theme.word, caps: theme.caps, maxWidth: 150)
                        .padding(.leading, 10)
                        .padding(.bottom, 17)
                }
                .clipShape(MoneyBannerShape())
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(MoneyFormat.percent(share))
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(theme.tintColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(theme.tintColor.opacity(0.25), lineWidth: 0.75))
                }
                Text(amount)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(pal.progressTrack)
                        Capsule()
                            .fill(LinearGradient(colors: [theme.topColor, theme.bottomColor],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, share)))))
                    }
                }
                .frame(height: 4)
                .padding(.top, 6)
                footer(pal)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 11)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04), lineWidth: 0.75)
        }
        .shadow(color: scheme == .dark ? Color.black.opacity(0.32) : Color(tb: 0x1E3A6E, 0.08),
                radius: 6, x: 0, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + "，" + amount + "，占 " + MoneyFormat.percent(share) + "，\(count) 筆"
                            + (change.map { "，比上月同期 " + $0 } ?? ""))
    }

    private func footer(_ pal: TripBoardPalette) -> some View {
        Group {
            if let change {
                Text("\(count) 筆・比上月同期 \(Text(change).foregroundStyle(changeTone.color(pal)))")
            } else {
                Text("\(count) 筆")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 一條分類比例的彩帶（明信片上面那條、圖表頁的甜甜圈下面）
struct MoneyShareRibbon: View {
    struct Segment: Equatable {
        let theme: MoneyArtTheme
        let value: Double
    }
    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
            let gap: CGFloat = 2
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, segments.count - 1)))
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                    LinearGradient(colors: [s.theme.topColor, s.theme.bottomColor],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: max(3, usable * CGFloat(s.value / total)))
                }
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - 一筆資料 → 卡片要寫的字

/// 卡片會用到的對照表（卡片名、銀行名、旅程名、旅程的站）。一頁算一次，傳給每一張卡。
struct MoneyItemContext {
    private let milestoneTitles: [UUID: String]
    private let cardNames: [UUID: String]
    private let bankNames: [UUID: String]
    private let tripTitles: [UUID: String]
    private let stops: [UUID: TripStop]
    private let rates: [String: Double]

    init(lifeStore: LifeStore, store: ExpenseStore) {
        var titles: [UUID: String] = [:]
        var cards: [UUID: String] = [:]
        var banks: [UUID: String] = [:]
        for m in lifeStore.milestones {
            titles[m.id] = m.title
            if let c = m.cardName { cards[m.id] = c }
            if let b = m.bankName { banks[m.id] = b }
        }
        milestoneTitles = titles
        cardNames = cards
        bankNames = banks
        var trips: [UUID: String] = [:]
        var stopMap: [UUID: TripStop] = [:]
        for p in lifeStore.tripPlans {
            trips[p.id] = p.title
            for s in p.stops { stopMap[s.id] = s }
        }
        tripTitles = trips
        stops = stopMap
        var r: [String: Double] = [:]
        for rate in store.currencyRates where r[rate.code] == nil {
            r[rate.code] = rate.rate
        }
        rates = r
    }

    func tripTitle(_ id: UUID?) -> String? { id.flatMap { tripTitles[$0] } }
    func stop(_ id: UUID?) -> TripStop? { id.flatMap { stops[$0] } }
    func rate(_ code: String) -> Double? { rates[code] }

    /// 信用卡用卡名、銀行用銀行名（＋外幣帳戶的幣別）；跟原本列表上的扣款膠囊同一個規則
    func payment(cardId: UUID?, bankId: UUID?, bankCurrency: String?) -> MoneyItemChip? {
        if let id = cardId, let title = milestoneTitles[id] {
            return MoneyItemChip(icon: "creditcard.fill", text: cardNames[id] ?? title)
        }
        if let id = bankId, let title = milestoneTitles[id] {
            let name = bankNames[id] ?? title
            let currency = bankCurrency ?? "NT$"
            return MoneyItemChip(icon: "building.columns.fill",
                                 text: currency == "NT$" ? name : name + " · " + currency)
        }
        return nil
    }
}

extension MoneyItem {
    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private static let dueFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"
        return f
    }()

    private static let endFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "yyyy/M"
        return f
    }()

    /// 金額：外幣輸入的照原幣顯示（存的是台幣等值，除回匯率）；儲蓄險存的本來就是原幣。
    /// 跟原本 ExpenseRow／FixedExpenseRow 的 formattedAmount 同一個規則。
    static func amountText(_ e: Expense, ctx: MoneyItemContext) -> String {
        let code = e.currencyCode
        guard code != "NT$", code != "TWD", !code.isEmpty else { return e.amount.ntdWanString }
        let isSavingsIns = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
        let value: Double
        if isSavingsIns {
            value = e.amount
        } else if let rate = ctx.rate(code), rate > 0 {
            value = e.amount / rate
        } else {
            value = e.amount
        }
        return code + " " + (decimal.string(from: NSNumber(value: value)) ?? "0")
    }

    /// 名稱：使用者打的名字照用（全域清單裡店名是唯一的地點線索，見 stopRowLabel 的說明）；
    /// 沒打名字才退到備註或分類名
    /// [v25.526] 拿掉 private：收支看板的「最大一筆」、列車的下一站也用這個名字
    static func title(_ e: Expense) -> String {
        let t = e.title.moneyTrimmed
        return t.isEmpty ? e.stopRowLabel(suppressing: []).primary : t
    }

    /// 變動支出（也用在總覽的最近交易）
    static func expense(_ e: Expense, ctx: MoneyItemContext, badge: String?) -> MoneyItem {
        let seed = Self.seed(e.id)
        let title = Self.title(e)
        // 位置：自己的座標，沒有就借綁定的那一站
        let stop = ctx.stop(e.linkedTripStopId)
        let lat = e.placeLatitude ?? stop?.latitude
        let lon = e.placeLongitude ?? stop?.longitude
        let address = (e.placeAddress?.moneyTrimmed).flatMap { $0.isEmpty ? nil : $0 }
            ?? (stop?.address.moneyTrimmed).flatMap { $0.isEmpty ? nil : $0 }
        let place = address.flatMap { TripPlaceName.parse($0) }

        // 副標：汽車的地點（加油站、停車場）、備註；都沒有才寫地址
        var parts: [String] = []
        if let p = e.placeName?.moneyTrimmed, !p.isEmpty, p != title { parts.append(p) }
        let memo = e.note.moneyTrimmed
        if !memo.isEmpty, memo != title { parts.append(memo) }
        if parts.isEmpty, let a = address { parts.append(TripCardText.addressWithoutPostal(a)) }

        var chips: [MoneyItemChip] = []
        if let pay = ctx.payment(cardId: e.linkedCreditCardMilestoneId, bankId: e.linkedBankMilestoneId,
                                 bankCurrency: e.linkedBankCurrency) {
            chips.append(pay)
        }
        if let m = e.diningMember?.moneyTrimmed, !m.isEmpty {
            chips.append(MoneyItemChip(icon: "person.2.fill", text: m))
        }
        if e.variableCategory == .social, let r = e.socialRecipient?.moneyTrimmed, !r.isEmpty {
            chips.append(MoneyItemChip(icon: "gift.fill", text: r))
        }
        let trip = ctx.tripTitle(e.linkedTripPlanId)
        if let trip {
            chips.append(MoneyItemChip(icon: "airplane", text: trip))
        }
        if let k = e.evKwh, k > 0 {
            chips.append(MoneyItemChip(icon: "bolt.car.fill", text: String(format: "%.1f kWh", k)))
        }
        let photos = e.photoFileNames.filter { !$0.lowercased().hasSuffix(".pdf") }
        if photos.count >= 2 {
            chips.append(MoneyItemChip(icon: "photo.on.rectangle", text: "\(photos.count)"))
        }

        return MoneyItem(
            id: e.id, theme: MoneyArtTheme.of(e), seed: seed, title: title,
            amount: amountText(e, ctx: ctx), category: e.categoryName,
            detail: parts.isEmpty ? nil : parts.joined(separator: "・"),
            badge: badge, chips: chips,
            photoURL: photos.first.map { Expense.photoURL(for: $0) },
            latitude: lat, longitude: lon, place: place,
            skyline: e.linkedTripPlanId != nil && trip != nil
                ? MoneyItemSkyline(landmarks: TripLandmark.forCity(place?.zh), seed: seed)
                : nil)
    }

    /// 固定支出
    static func fixed(_ e: Expense, ctx: MoneyItemContext, financeStore: FinanceStore,
                      now: Date = Date()) -> MoneyItem {
        let seed = Self.seed(e.id)
        let title = Self.title(e)
        let theme = MoneyArtTheme.of(e.fixedCategory)
        let cal = Calendar.current
        let isSavingsIns = e.fixedCategory == .insurance && e.insuranceSubCategory == .savings
        let foreign = e.currencyCode != "NT$" && e.currencyCode != "TWD" && !e.currencyCode.isEmpty

        let unit: String?
        switch e.recurrence {
        case .monthly: unit = "/月"
        case .quarterly: unit = "/季"
        case .yearly: unit = "/年"
        case .none: unit = nil
        }

        var chips: [MoneyItemChip] = []
        if e.isFixedEnded {
            chips.append(MoneyItemChip(icon: "stop.circle.fill", text: e.endReason?.rawValue ?? "已停止",
                                       tone: .warn))
        } else if let due = e.nextFixedDueDate(onOrAfter: now, calendar: cal) {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: due)).day ?? 0
            let text: String
            switch days {
            case ...0: text = "今天扣款"
            case 1: text = "明天扣款"
            case 2...31: text = dueFmt.string(from: due) + "・\(days) 天後"
            default: text = dueFmt.string(from: due) + " 扣款"
            }
            chips.append(MoneyItemChip(icon: "calendar", text: text, tone: days <= 1 ? .warn : .neutral))
        }
        // 季繳、年繳：月均
        if let rec = e.recurrence, rec != .monthly {
            let monthly: Double = rec == .quarterly ? e.amount / 3 : e.amount / 12
            if monthly > 0 {
                let text = isSavingsIns && foreign
                    ? e.currencyCode + " " + (decimal.string(from: NSNumber(value: monthly)) ?? "0")
                    : monthly.ntdWanString
                chips.append(MoneyItemChip(icon: "arrow.down.to.line", text: "月均 " + text))
            }
        }
        if let pay = ctx.payment(cardId: e.linkedCreditCardMilestoneId, bankId: e.linkedBankMilestoneId,
                                 bankCurrency: e.linkedBankCurrency) {
            chips.append(pay)
        }
        if e.effectivelyTaxDeductible {
            chips.append(MoneyItemChip(icon: "leaf.fill", text: "節稅", tone: .good))
        }

        // 繳費進度：貸款（年期，或總額 ÷ 月付）、儲蓄險（連結保單的期數）
        var progress: MoneyItemProgress? = nil
        if e.fixedCategory == .loan {
            if let s = e.moneyLoanSchedule(now: now, calendar: cal) {
                progress = MoneyItemProgress(
                    fraction: Double(s.elapsed) / Double(s.total),
                    leading: s.isDone ? "已繳清" : "已繳 \(s.elapsed)／\(s.total) 期",
                    trailing: s.isDone || s.left <= 0 ? nil : "還要繳 " + s.left.ntdWanString)
            }
        } else if isSavingsIns {
            let ins = e.linkedInsuranceId.flatMap { id in financeStore.insurances.first { $0.id == id } }
                ?? financeStore.insurances.first { $0.linkedExpenseId == e.id }
            if let ins, ins.totalPeriods > 0 {
                let elapsed = ins.elapsedPeriods
                let total = ins.totalPeriods
                progress = MoneyItemProgress(
                    fraction: min(1, Double(elapsed) / Double(total)),
                    leading: elapsed >= total ? "已繳滿" : "已繳 \(elapsed)／\(total) 期",
                    trailing: nil)
            }
        }

        var detail: String? = nil
        let memo = e.note.moneyTrimmed
        if !memo.isEmpty, memo != title {
            detail = memo
        } else if e.fixedCategory == .loan, let rate = e.loanRate, rate > 0 {
            detail = String(format: "利率 %.3g%%", rate)
        }

        var monogram: String? = nil
        if e.fixedCategory == .subscription, let first = title.first {
            monogram = String(first).uppercased()
        }

        return MoneyItem(
            id: e.id, theme: theme, seed: seed, title: title,
            amount: amountText(e, ctx: ctx), unit: unit, category: e.categoryName,
            detail: detail, badge: e.recurrence?.rawValue, chips: chips,
            photoURL: e.photoFileNames.first { !$0.lowercased().hasSuffix(".pdf") }
                .map { Expense.photoURL(for: $0) },
            monogram: monogram, progress: progress, dimmed: e.isFixedEnded)
    }

    /// 收入
    static func income(_ i: Income, ctx: MoneyItemContext, badge: String?, now: Date = Date()) -> MoneyItem {
        let seed = Self.seed(i.id)
        let t = i.title.moneyTrimmed
        var chips: [MoneyItemChip] = []
        if let pay = ctx.payment(cardId: nil, bankId: i.linkedBankMilestoneId,
                                 bankCurrency: i.linkedBankCurrency) {
            chips.append(pay)
        }
        if i.period != .once {
            chips.append(MoneyItemChip(icon: "repeat", text: i.period.rawValue))
        }
        var ended = false
        if i.isFixedSalary, let end = i.endDate {
            ended = !i.isActive(in: now)
            let label = (i.endReason?.rawValue ?? "結束") + " " + endFmt.string(from: end)
            chips.append(MoneyItemChip(icon: i.endReason?.icon ?? "calendar.badge.exclamationmark",
                                       text: label, tone: ended ? .neutral : .warn))
        }
        if i.linkedStockId != nil {
            chips.append(MoneyItemChip(icon: "chart.line.uptrend.xyaxis", text: "連結股票"))
        }
        let memo = i.note.moneyTrimmed
        return MoneyItem(
            id: i.id, theme: MoneyArtTheme.of(i.category), seed: seed,
            title: t.isEmpty ? i.category.rawValue : t,
            amount: "+" + i.amount.ntdWanString, amountStyle: .income,
            category: i.category.rawValue,
            detail: memo.isEmpty || memo == t ? nil : memo,
            badge: badge, chips: chips, dimmed: ended)
    }
}

// MARK: - 貸款的期數（v25.526 從 MoneyItem.fixed 抽出來：固定支出看板的「貸款還要繳」也要用）

struct MoneyLoanSchedule: Equatable {
    /// 已經繳了幾期（起始那個月算第一期）
    let elapsed: Int
    let total: Int
    /// 每月要繳多少（季繳 ÷ 3、年繳 ÷ 12）
    let monthly: Double

    var isDone: Bool { elapsed >= total }
    /// 剩下的期數 × 月付
    var left: Double { Double(max(0, total - elapsed)) * monthly }
}

extension Expense {
    /// 貸款繳到第幾期：期數看年期，沒有年期就用總額 ÷ 月付。不是貸款、或兩個都沒填是 nil。
    func moneyLoanSchedule(now: Date = Date(), calendar cal: Calendar = .current) -> MoneyLoanSchedule? {
        guard fixedCategory == .loan else { return nil }
        let monthly: Double
        switch recurrence {
        case .monthly: monthly = amount
        case .quarterly: monthly = amount / 3
        case .yearly: monthly = amount / 12
        case .none: monthly = 0
        }
        var totalMonths = 0
        if let years = loanYears, years > 0 {
            totalMonths = Int((years * 12).rounded())
        } else if let total = loanTotalAmount, total > 0, monthly > 0 {
            totalMonths = Int((total / monthly).rounded())
        }
        guard totalMonths > 0 else { return nil }
        let months = cal.dateComponents([.month], from: date, to: now).month ?? 0
        let elapsed = max(0, min(months + 1, totalMonths))
        return MoneyLoanSchedule(elapsed: elapsed, total: totalMonths, monthly: monthly)
    }
}
