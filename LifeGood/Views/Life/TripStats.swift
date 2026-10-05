import SwiftUI

// MARK: - 共用零件（v25.480）
//
// 相簿與花費兩張統計頁共用這三個零件。各自手刻一份的話，兩頁的磚會各長各的，
// 改一個樣式要改兩處——這是本專案在 ItemRow／HeroKpiCell 已經學過的教訓。

/// 統計磚：標題、一個大數字、一行小註。
struct TripStatTile: View {
    let icon: String
    let value: String
    let label: String
    var note: String? = nil
    var tint: Color = .indigo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.55)
            if let note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemFill).opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 佔比橫條。長度是「佔最大那一項的比例」而不是佔總和——
/// 十幾個分類時佔總和的條會全部細到看不出差別。
struct TripShareBar: View {
    let label: String
    let value: String
    /// 0...1
    let fraction: Double
    var tint: Color = .indigo
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
        }
    }
}

/// 統計卡外框。樣式對齊行程頁其餘的白卡。
struct TripStatsCard<Content: View>: View {
    let title: String
    let icon: String
    var accent: Color = .indigo
    var footnote: String? = nil
    /// 左右外距。整頁捲動時是 16；嵌在別的容器裡（相簿看板）傳 0，
    /// 不然會多縮一層——用負的 padding 去抵銷是最難維護的那種寫法。
    var outerPadding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 15)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            content()
            if let footnote {
                Text(footnote)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, outerPadding)
    }
}

/// 「這是第幾天」。相簿與花費都要把日期換算成天數，規則集中在這裡。
enum TripDayMath {
    /// 落在這趟的第幾天（0 起算）；不在期間內回 nil
    static func dayIndex(_ date: Date, in plan: TripPlan) -> Int? {
        let cal = Calendar.current
        guard let d = cal.dateComponents([.day],
                                         from: cal.startOfDay(for: plan.startDate),
                                         to: cal.startOfDay(for: date)).day,
              d >= 0, d < max(plan.dayCount, 1) else { return nil }
        return d
    }

    /// 「第 3 天 10/5」
    static func dayLabel(_ index: Int, in plan: TripPlan) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index,
                                         to: plan.startDate) ?? plan.startDate
        return "第 \(index + 1) 天 " + shortDay.string(from: date)
    }

    static let shortDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d"; return f
    }()
}

// MARK: - 相簿統計看板（v25.480）

/// 相簿頂端的統計看板。掛在共用的 MapAlbumSheet 上（它多了一個 stats 插槽）。
///
/// 只讀 items 與 plan，不自己去翻 store：相簿顯示的是哪些照片由呼叫端決定
/// （景點照片＋掛在這趟的花費照片），統計要跟畫面上看到的那一堆一致。
struct TripAlbumStatsPanel: View {
    let plan: TripPlan
    let items: [AlbumPhotoItem]

    /// 花費照片的 id 由呼叫端加了前綴（見 TripPlanView.albumItems）
    private var expensePhotos: Int { items.filter { $0.id.hasPrefix("expense-") }.count }
    private var stopPhotos: Int { items.count - expensePhotos }
    private var stopsWithPhotos: Int { plan.stops.filter { !$0.photoFileNames.isEmpty }.count }

    /// 每一組（景點）幾張，多的排前面
    private var byGroup: [(name: String, count: Int)] {
        var map: [String: Int] = [:]
        for item in items { map[item.group.isEmpty ? "未命名" : item.group, default: 0] += 1 }
        return map.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// 每一天幾張
    private var byDay: [(day: Int, count: Int)] {
        var map: [Int: Int] = [:]
        for item in items {
            guard let d = TripDayMath.dayIndex(item.date, in: plan) else { continue }
            map[d, default: 0] += 1
        }
        return map.map { (day: $0.key, count: $0.value) }.sorted { $0.day < $1.day }
    }

    private var perDayAverage: String {
        let days = max(plan.dayCount, 1)
        return String(format: "%.1f", Double(items.count) / Double(days))
    }

    var body: some View {
        VStack(spacing: 10) {
            tiles
            if (byGroup.first?.count ?? 0) > 0 { placeCard }
            if byDay.count > 1 { dayCard }
            sourceCard
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            TripStatTile(icon: "photo.stack", value: "\(items.count)", label: "照片",
                         note: "每天平均 " + perDayAverage + " 張", tint: .purple)
            TripStatTile(icon: "mappin.and.ellipse", value: "\(stopsWithPhotos)",
                         label: "有照片的景點",
                         note: "全程 \(plan.stops.count) 站", tint: .indigo)
            TripStatTile(icon: "calendar", value: "\(byDay.count)", label: "有拍到的天數",
                         note: "共 \(plan.dayCount) 天", tint: .teal)
        }
    }

    private var placeCard: some View {
        TripStatsCard(title: "拍最多的地方", icon: "crown.fill", accent: .orange,
                      outerPadding: 0) {
            let top = Array(byGroup.prefix(5))
            let most = Double(top.first?.count ?? 1)
            VStack(spacing: 8) {
                ForEach(top, id: \.name) { row in
                    TripShareBar(label: row.name, value: "\(row.count) 張",
                                 fraction: most > 0 ? Double(row.count) / most : 0,
                                 tint: .orange)
                }
            }
        }
    }

    private var dayCard: some View {
        TripStatsCard(title: "每天拍了多少", icon: "chart.bar.fill", accent: .teal,
                      outerPadding: 0) {
            let most = Double(byDay.map(\.count).max() ?? 1)
            VStack(spacing: 8) {
                ForEach(byDay, id: \.day) { row in
                    TripShareBar(label: TripDayMath.dayLabel(row.day, in: plan),
                                 value: "\(row.count) 張",
                                 fraction: most > 0 ? Double(row.count) / most : 0,
                                 tint: TripDayPalette.color(row.day))
                }
            }
        }
    }

    private var sourceCard: some View {
        TripStatsCard(title: "照片從哪來", icon: "tray.full.fill", accent: .purple,
                      footnote: "花費的照片留在記帳那邊，相簿只是多一個看得到的入口——"
                          + "在這裡刪不掉它們。",
                      outerPadding: 0) {
            let total = Double(max(items.count, 1))
            VStack(spacing: 8) {
                TripShareBar(label: "景點照片", value: "\(stopPhotos) 張",
                             fraction: Double(stopPhotos) / total, tint: .purple)
                TripShareBar(label: "花費照片", value: "\(expensePhotos) 張",
                             fraction: Double(expensePhotos) / total, tint: .green)
            }
        }
    }
}

// MARK: - 花費統計頁（v25.480）

/// 這趟的花費：頂端是量級，底下依分類／天／站／幣別拆開，最後才是明細。
///
/// 為什麼獨立一頁而不是繼續掛在行程頁底下：行程頁的主角是時間軸，
/// 一趟七天的行程把幾十筆花費攤在同一個捲動裡，兩邊都看不好。
struct TripExpenseSheet: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let planId: UUID

    @State private var editing: Expense?

    private let accent = TripDayPalette.color(0)

    private var plan: TripPlan? { lifeStore.tripPlan(id: planId) }

    /// 掛在這趟上的（新到舊）
    private var linked: [Expense] {
        expenseStore.expenses
            .filter { $0.linkedTripPlanId == planId }
            .sorted { $0.date > $1.date }
    }

    /// 日期落在期間內、還沒關聯任何旅遊的變動支出
    private var candidates: [Expense] {
        guard let p = plan else { return [] }
        let cal = Calendar.current
        let from = cal.startOfDay(for: p.startDate)
        let to = cal.startOfDay(for: p.endDate)
        return expenseStore.expenses
            .filter { e in
                guard e.expenseType == .variable, e.linkedTripPlanId == nil else { return false }
                let day = cal.startOfDay(for: e.date)
                return day >= from && day <= to
            }
            .sorted { $0.date > $1.date }
    }

    private var total: Double { expenseStore.ntdTotal(linked) }

    var body: some View {
        NavigationStack {
            Group {
                if let p = plan {
                    ScrollView {
                        VStack(spacing: 14) {
                            heroCard(p)
                            if !linked.isEmpty {
                                categoryCard
                                dayCard(p)
                                stopCard(p)
                                currencyCard
                            }
                            if !candidates.isEmpty { candidateCard(p) }
                            listCard
                        }
                        .padding(.vertical)
                    }
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("這趟的花費")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
            .sheet(item: $editing) { e in
                AddExpenseView(expenseType: e.expenseType, editingExpense: e)
            }
        }
    }

    // MARK: 量級

    private func heroCard(_ p: TripPlan) -> some View {
        let days = max(p.dayCount, 1)
        let perDay = total / Double(days)
        let largest = linked.max { expenseStore.ntdValue(of: $0) < expenseStore.ntdValue(of: $1) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("這趟總共花了")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                Text(total.ntdWanString)
                    .heroBigValueFont()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: 0) {
                HeroKpiCell(label: "筆數", value: "\(linked.count)", icon: "list.bullet")
                HeroKpiDivider()
                HeroKpiCell(label: "每天平均", value: perDay.ntdWanString, icon: "calendar")
                HeroKpiDivider()
                HeroKpiCell(label: "最大一筆",
                            value: largest.map { expenseStore.ntdValue(of: $0).ntdWanString } ?? "—",
                            icon: "arrow.up.right")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let largest {
                Text("最大一筆：" + title(of: largest) + "・"
                     + TripDayMath.shortDay.string(from: largest.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .heroCardShell(card: .tripPlan)
        .padding(.horizontal, 16)
    }

    // MARK: 分類

    private var categoryCard: some View {
        var map: [VariableCategory: Double] = [:]
        for e in linked {
            guard let c = e.variableCategory else { continue }
            map[c, default: 0] += expenseStore.ntdValue(of: e)
        }
        let rows = map.map { (cat: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
        let most = rows.first?.amount ?? 1
        return TripStatsCard(title: "花在哪些分類", icon: "chart.pie.fill", accent: .orange) {
            VStack(spacing: 8) {
                ForEach(rows, id: \.cat) { row in
                    TripShareBar(
                        label: row.cat.rawValue,
                        value: row.amount.ntdWanString,
                        fraction: most > 0 ? row.amount / most : 0,
                        tint: row.cat.accentColor,
                        sub: percentText(row.amount))
                }
            }
        }
    }

    // MARK: 每天

    private func dayCard(_ p: TripPlan) -> some View {
        var map: [Int: Double] = [:]
        for e in linked {
            guard let d = TripDayMath.dayIndex(e.date, in: p) else { continue }
            map[d, default: 0] += expenseStore.ntdValue(of: e)
        }
        let rows = map.map { (day: $0.key, amount: $0.value) }.sorted { $0.day < $1.day }
        let most = rows.map(\.amount).max() ?? 1
        return TripStatsCard(title: "哪一天花最多", icon: "calendar.badge.clock", accent: .teal,
                             footnote: rows.count < p.dayCount
                                ? "沒有出現的日子代表那一天沒有掛上任何花費。" : nil) {
            VStack(spacing: 8) {
                ForEach(rows, id: \.day) { row in
                    TripShareBar(label: TripDayMath.dayLabel(row.day, in: p),
                                 value: row.amount.ntdWanString,
                                 fraction: most > 0 ? row.amount / most : 0,
                                 tint: TripDayPalette.color(row.day),
                                 sub: percentText(row.amount))
                }
            }
        }
    }

    // MARK: 每一站

    private func stopCard(_ p: TripPlan) -> some View {
        var map: [UUID: Double] = [:]
        var unassigned: Double = 0
        for e in linked {
            let v = expenseStore.ntdValue(of: e)
            if let sid = e.linkedTripStopId, p.stops.contains(where: { $0.id == sid }) {
                map[sid, default: 0] += v
            } else {
                unassigned += v
            }
        }
        let rows = map.compactMap { (id, amount) -> (id: UUID, name: String, amount: Double)? in
            guard let stop = p.stops.first(where: { $0.id == id }) else { return nil }
            return (id: id, name: stop.displayName, amount: amount)
        }.sorted { $0.amount > $1.amount }
        let most = max(rows.first?.amount ?? 0, unassigned)
        return TripStatsCard(title: "花在哪幾站", icon: "mappin.circle.fill", accent: .pink,
                             footnote: unassigned > 0
                                ? "「整趟（未指定）」是記帳時沒有挑站別的那些。到那一筆把站別補上就會歸位。"
                                : nil) {
            VStack(spacing: 8) {
                ForEach(rows.prefix(8), id: \.id) { row in
                    TripShareBar(label: row.name, value: row.amount.ntdWanString,
                                 fraction: most > 0 ? row.amount / most : 0,
                                 tint: .pink, sub: percentText(row.amount))
                }
                if unassigned > 0 {
                    TripShareBar(label: "整趟（未指定）", value: unassigned.ntdWanString,
                                 fraction: most > 0 ? unassigned / most : 0,
                                 tint: .gray, sub: percentText(unassigned))
                }
            }
        }
    }

    // MARK: 幣別

    private var currencyCard: some View {
        var map: [String: (amount: Double, count: Int)] = [:]
        for e in linked {
            let code = e.currencyCode.isEmpty ? "NT$" : e.currencyCode
            let old = map[code] ?? (amount: 0, count: 0)
            map[code] = (amount: old.amount + expenseStore.ntdValue(of: e), count: old.count + 1)
        }
        let rows = map.map { (code: $0.key, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
        let most = rows.first?.amount ?? 1
        return TripStatsCard(title: "用了哪些幣別", icon: "dollarsign.circle.fill", accent: .green,
                             footnote: "條上的金額一律是台幣等值（用設定裡的匯率換算）。"
                                + "明細那邊寫的才是你當初輸入的原幣金額。") {
            VStack(spacing: 8) {
                ForEach(rows, id: \.code) { row in
                    TripShareBar(label: row.code, value: row.amount.ntdWanString,
                                 fraction: most > 0 ? row.amount / most : 0,
                                 tint: .green, sub: "\(row.count) 筆")
                }
            }
        }
    }

    // MARK: 還沒掛上的

    private func candidateCard(_ p: TripPlan) -> some View {
        TripStatsCard(title: "期間內還有 \(candidates.count) 筆沒掛上",
                      icon: "questionmark.circle.fill", accent: .orange,
                      footnote: "只列日期落在這趟期間內的變動支出。旅行期間在家附近的加油、"
                          + "網購也會落在同一段日期裡，所以不自動掛——要算進這趟的才按＋。") {
            VStack(spacing: 0) {
                HStack {
                    Text(expenseStore.ntdTotalText(candidates))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("全部掛上") {
                        for e in candidates { link(e, to: p.id) }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                }
                .padding(.bottom, 6)
                ForEach(candidates) { e in
                    row(e, trailing: {
                        Button {
                            link(e, to: p.id)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18)).foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    })
                }
            }
        }
    }

    // MARK: 明細

    private var listCard: some View {
        TripStatsCard(title: "明細 \(linked.count) 筆", icon: "list.bullet.rectangle", accent: accent,
                      footnote: linked.isEmpty
                        ? "還沒有花費掛在這趟上。記帳時在「旅遊」那一區挑這趟行程，或從時間軸每一站的購物車直接記。"
                        : "點一筆可以編輯（含關聯的站別）。") {
            VStack(spacing: 0) {
                ForEach(linked) { e in
                    Button {
                        editing = e
                    } label: {
                        row(e, trailing: {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 列與小工具

    private func row<Trailing: View>(_ e: Expense,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: e))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(TripDayMath.shortDay.string(from: e.date))
                        .font(.caption2).foregroundStyle(.secondary)
                    if let c = e.variableCategory {
                        Text(c.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(c.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(c.accentColor)
                    }
                    if let sid = e.linkedTripStopId,
                       let stop = plan?.stops.first(where: { $0.id == sid }) {
                        Text(stop.displayName)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !e.photoFileNames.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "photo").font(.system(size: 8))
                            Text("\(e.photoFileNames.count)")
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(expenseStore.displayAmountText(e))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            trailing()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func title(of e: Expense) -> String {
        e.title.isEmpty ? (e.variableCategory?.rawValue ?? "花費") : e.title
    }

    private func percentText(_ amount: Double) -> String? {
        guard total > 0 else { return nil }
        return String(format: "%.0f%%", amount / total * 100)
    }

    private func link(_ e: Expense, to tripId: UUID) {
        var updated = e
        updated.linkedTripPlanId = tripId
        expenseStore.update(updated)
    }
}
