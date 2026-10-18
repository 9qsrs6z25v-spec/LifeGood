//
//  VehicleResaleView.swift
//  LifeGood
//
//  [賣車估價] 車輛卡的「賣車估價」頁：估價結果、我的車、選配清單、市場上看到的車、怎麼算的。
//  - 字和數字全在 VehicleResaleReport.build 算好（VehicleResale.swift），這裡只排版、開編輯頁、寫回 store。
//  - 頁面本身只看不改；改東西都開編輯頁（Form），按「儲存」先關頁、下一個 runloop 才寫 FinanceStore
//    （同 VehiclePhotoEditor：關 sheet 的交易裡同步改 @Published store 容易閃退）。
//  - 選配是一份共用清單：我的車、每台市場上的車都只是打勾；編輯頁最下面可以直接加清單上沒有的。
//  - 彈出頁一個 .sheet(item:)，內容一律包 .appStores()；確認框一個 VehicleResaleConfirm。
//  - 付費由車輛卡擋（打開這頁前 requirePremium），這頁本身不擋。
//

import SwiftUI

// MARK: - 車輛卡上的入口

/// 車輛卡「賣車估價」那一區（持有中的車才有）：一張白卡、一行說明，點了打開估價頁（付費在外殼擋）
struct VehicleResaleEntryCard: View {
    let subtitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "賣車估價")
            Button(action: action) {
                label
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下打開賣車估價")
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Color(tb: 0x2F7FE8), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("我的車可以標多少？")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
        .modifier(FinanceCardChrome())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 賣車估價頁

struct VehicleResaleView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: UUID

    @State private var sheet: VehicleResaleSheet?
    @State private var confirm: VehicleResaleConfirm?

    /// 顯式 init：車輛卡（別的檔案）呼叫，不靠 memberwise
    init(vehicleId: UUID) {
        self.vehicleId = vehicleId
    }

    private var vehicle: Vehicle? {
        store.vehicles.first(where: { $0.id == vehicleId })
    }

    var body: some View {
        NavigationStack {
            presented(page)
        }
    }

    private var page: some View {
        content
            .navigationTitle("賣車估價")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
    }

    private func presented<Content: View>(_ base: Content) -> some View {
        base
            .sheet(item: $sheet) { s in sheetView(s).appStores() }
            .alert(confirm?.title ?? "", isPresented: confirmShown, presenting: confirm) { c in
                confirmButtons(c)
            } message: { c in
                Text(c.message)
            }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("關閉") { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let v = vehicle {
            scroller(v)
        } else {
            Text("找不到這台車")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
    }

    private func scroller(_ v: Vehicle) -> some View {
        let report = makeReport(v)
        return ScrollView {
            sections(report)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sections(_ report: VehicleResaleReport) -> some View {
        VStack(spacing: 22) {
            VehicleResaleSummarySection(report: report, onApply: { askApply(report) })
            VehicleResaleMyCarSection(car: report.myCar, onEdit: { openMyCar() })
            VehicleResaleCatalogSection(report: report, onEdit: { openCatalog() },
                                        onTemplates: { openTemplates() })
            VehicleResaleListingsSection(report: report, onAdd: { openListing(nil) },
                                         onEdit: { id in openListing(id) },
                                         onDelete: { item in askDelete(item) })
            VehicleResaleFootnote(lines: report.footnotes)
        }
    }

    // MARK: 資料

    private func makeReport(_ v: Vehicle) -> VehicleResaleReport {
        VehicleResaleReport.build(vehicle: v, workspace: workspace(v), isSaved: v.resale != nil, today: Date())
    }

    /// 存過的那一份；還沒存過就從車輛資料帶一份起點（第一次按儲存才真的寫進去）
    private func workspace(_ v: Vehicle) -> VehicleResaleWorkspace {
        if let saved = v.resale { return saved }
        return VehicleResaleWorkspace.starting(from: v, odometerKm: latestOdometer?.km,
                                               calendar: VehicleResaleText.calendar)
    }

    /// 記帳裡這台車最近一次里程錶（我的車帶入里程用）
    private var latestOdometer: VehicleOdometer.Reading? {
        let list = expenseStore.expenses.filter { $0.linkedVehicleId == vehicleId }
        return VehicleOdometer(expenses: list, calendar: VehicleResaleText.calendar).readings.last
    }

    // MARK: 打開編輯頁

    private func openMyCar() { sheet = .myCar(UUID()) }
    private func openCatalog() { sheet = .catalog(UUID()) }
    private func openTemplates() { sheet = .templates(UUID()) }

    private func openListing(_ id: UUID?) {
        var existing: VehicleResaleListing? = nil
        if let id, let ws = vehicle?.resale {
            existing = ws.listings.first(where: { $0.id == id })
        }
        sheet = .listing(UUID(), existing)
    }

    @ViewBuilder
    private func sheetView(_ s: VehicleResaleSheet) -> some View {
        if let v = vehicle {
            switch s {
            case .myCar:
                myCarEditor(v)
            case .listing(_, let listing):
                listingEditor(v, listing: listing)
            case .catalog:
                catalogEditor(v)
            case .templates:
                templateSheet(v)
            }
        }
    }

    private func myCarEditor(_ v: Vehicle) -> some View {
        VehicleResaleMyCarEditor(vehicleName: VehicleResaleReport.displayName(v), start: workspace(v),
                                 odometer: latestOdometer, onSave: { edit in saveMyCar(edit) })
    }

    private func listingEditor(_ v: Vehicle, listing: VehicleResaleListing?) -> some View {
        let ws = workspace(v)
        return VehicleResaleListingEditor(editing: listing, catalog: ws.options, myOptionIds: ws.myOptionIds,
                                          onSave: { l, added in saveListing(l, added: added) },
                                          onDelete: { id in deleteListing(id) })
    }

    private func catalogEditor(_ v: Vehicle) -> some View {
        let ws = workspace(v)
        return VehicleResaleCatalogEditor(options: ws.options, usage: VehicleResaleMath.usage(ws),
                                          onSave: { list in saveCatalog(list) })
    }

    private func templateSheet(_ v: Vehicle) -> some View {
        let ws = workspace(v)
        let existing = Set(ws.options.map { VehicleResaleMath.key($0.name) })
        let guessed = VehicleOptionTemplates.guess(name: v.name, brand: v.brand)
        return VehicleResaleTemplateSheet(existing: existing, guessed: guessed,
                                          onAdd: { names in addTemplates(names) })
    }

    // MARK: 寫回 store（一律排到下一個 runloop、讀最新的那台車）

    private func persist(_ change: @escaping (inout VehicleResaleWorkspace) -> Void) {
        let finance = store
        let id = vehicleId
        let odometerKm = latestOdometer?.km
        DispatchQueue.main.async {
            guard var v = finance.vehicles.first(where: { $0.id == id }) else { return }
            var ws = v.resale ?? VehicleResaleWorkspace.starting(from: v, odometerKm: odometerKm,
                                                                 calendar: VehicleResaleText.calendar)
            change(&ws)
            ws.updatedAt = Date()
            v.resale = ws
            finance.update(v)
        }
    }

    /// 編輯頁新加的選配接到共用清單最後面（同一個 id 已經在清單上就不重複加）
    private static func merge(_ added: [VehicleResaleOption], into ws: inout VehicleResaleWorkspace) {
        let ids = Set(ws.options.map(\.id))
        for o in added where !ids.contains(o.id) {
            ws.options.append(o)
        }
    }

    private func saveMyCar(_ edit: VehicleResaleMyCarEdit) {
        persist { ws in
            Self.merge(edit.added, into: &ws)
            ws.builtYear = edit.builtYear
            ws.builtMonth = edit.builtMonth
            ws.newPrice = edit.newPrice
            ws.mileageKm = edit.mileageKm
            ws.myOptionIds = edit.optionIds
        }
    }

    private func saveListing(_ l: VehicleResaleListing, added: [VehicleResaleOption]) {
        persist { ws in
            Self.merge(added, into: &ws)
            if let i = ws.listings.firstIndex(where: { $0.id == l.id }) {
                ws.listings[i] = l
            } else {
                ws.listings.append(l)
            }
        }
    }

    private func deleteListing(_ id: UUID) {
        persist { ws in
            ws.listings.removeAll { $0.id == id }
        }
    }

    /// 選配清單整份換掉；刪掉的選配也從我的車、每台市場上的車的勾選拿掉
    private func saveCatalog(_ list: [VehicleResaleOption]) {
        persist { ws in
            ws.options = list
            let keep = Set(list.map(\.id))
            ws.myOptionIds = ws.myOptionIds.filter { keep.contains($0) }
            for i in ws.listings.indices {
                ws.listings[i].optionIds = ws.listings[i].optionIds.filter { keep.contains($0) }
            }
        }
    }

    /// 範本的名稱加進清單（原價空白）；同名的不重複加
    private func addTemplates(_ names: [String]) {
        persist { ws in
            var keys = Set(ws.options.map { VehicleResaleMath.key($0.name) })
            for n in names where !keys.contains(VehicleResaleMath.key(n)) {
                ws.options.append(VehicleResaleOption(name: n))
                keys.insert(VehicleResaleMath.key(n))
            }
        }
    }

    // MARK: 確認框

    private var confirmShown: Binding<Bool> {
        Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
    }

    @ViewBuilder
    private func confirmButtons(_ c: VehicleResaleConfirm) -> some View {
        Button(c.button, role: c.destructive ? .destructive : nil) { c.action() }
        Button("取消", role: .cancel) {}
    }

    private func askApply(_ report: VehicleResaleReport) {
        guard let s = report.summary else { return }
        let price = s.suggested
        confirm = VehicleResaleConfirm(title: "把車輛估值改成 \(s.suggestedText)？", message: report.applyMessage,
                                       button: "設為估值", destructive: false,
                                       action: { applyValue(price) })
    }

    /// 估值寫進車子（估值更新日一起寫今天：車輛資料「2026/10 更新」、超過一年提醒都看它）
    private func applyValue(_ price: Double) {
        let finance = store
        let id = vehicleId
        DispatchQueue.main.async {
            guard var v = finance.vehicles.first(where: { $0.id == id }) else { return }
            v.currentValue = price
            v.valueUpdatedAt = Date()
            finance.update(v)
        }
    }

    private func askDelete(_ item: VehicleResaleReport.Listing) {
        let id = item.id
        confirm = VehicleResaleConfirm(title: "刪除「\(item.title)」？", message: "這台的資料會刪掉，估價會重算。",
                                       button: "刪除", destructive: true,
                                       action: { deleteListing(id) })
    }
}

// MARK: - 彈出頁、確認框的型別

/// 每次打開都帶一個新的 UUID：跟「打開」綁在一起，不會帶到上一次的內容
private enum VehicleResaleSheet: Identifiable {
    case myCar(UUID)
    case listing(UUID, VehicleResaleListing?)
    case catalog(UUID)
    case templates(UUID)

    var id: String {
        switch self {
        case .myCar(let token): return "myCar-" + token.uuidString
        case .listing(let token, _): return "listing-" + token.uuidString
        case .catalog(let token): return "catalog-" + token.uuidString
        case .templates(let token): return "templates-" + token.uuidString
        }
    }
}

private struct VehicleResaleConfirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    var destructive = false
    let action: () -> Void
}

// MARK: - 估價結果

private struct VehicleResaleSummarySection: View {
    let report: VehicleResaleReport
    let onApply: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "估價結果", trailing: report.summary?.countText)
            card(pal)
        }
    }

    @ViewBuilder
    private func card(_ pal: TripBoardPalette) -> some View {
        if let s = report.summary {
            filled(s, pal: pal)
        } else {
            empty
        }
    }

    private func filled(_ s: VehicleResaleReport.Summary, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headline(s, pal: pal)
            Divider().padding(.leading, 14)
            VehicleResaleRows(rows: s.rows)
            hintRow(s.hint, pal: pal)
            Divider().padding(.leading, 14)
            VehicleResaleRowView(row: report.valueRow)
            applyRow(s, pal: pal)
        }
        .modifier(FinanceCardChrome())
    }

    private func headline(_ s: VehicleResaleReport.Summary, pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("建議標價")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(s.suggestedText)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(MoneyTone.good.color(pal))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(s.suggestedDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func hintRow(_ hint: String?, pal: TripBoardPalette) -> some View {
        if let hint {
            Divider().padding(.leading, 14)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle.fill")
                Text(hint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MoneyTone.warn.color(pal))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }

    /// 「把建議標價設為車輛估值」；已經一樣時寫一行綠勾；建議標價 NT$0（換算被扣到 0）兩個都不放
    @ViewBuilder
    private func applyRow(_ s: VehicleResaleReport.Summary, pal: TripBoardPalette) -> some View {
        if report.canApply {
            Divider().padding(.leading, 14)
            Button(action: onApply) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("把建議標價設為車輛估值")
                    Spacer(minLength: 0)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pal.hint)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(MoneyPressStyle())
        } else if s.suggested > 0 {
            Divider().padding(.leading, 14)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("車輛估值已經是建議標價")
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MoneyTone.good.color(pal))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "tag")
                Text(report.emptyText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(14)
            .accessibilityElement(children: .combine)
            Divider().padding(.leading, 14)
            VehicleResaleRowView(row: report.valueRow)
        }
        .modifier(FinanceCardChrome())
    }
}

// MARK: - 我的車

private struct VehicleResaleMyCarSection: View {
    let car: VehicleResaleReport.MyCar
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "我的車")
            Button(action: onEdit) {
                card(pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下編輯我的車和選配")
        }
    }

    private func card(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VehicleResaleRows(rows: car.rows)
            optionsBlock(pal)
            editRow(pal)
        }
        .contentShape(Rectangle())
        .modifier(FinanceCardChrome())
    }

    @ViewBuilder
    private func optionsBlock(_ pal: TripBoardPalette) -> some View {
        if !car.options.isEmpty {
            Divider().padding(.leading, 14)
            Text("我勾的選配")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(pal.label)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            ForEach(car.options) { o in
                VehicleResaleOptionRowView(row: o, pal: pal)
            }
        }
    }

    private func editRow(_ pal: TripBoardPalette) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 14)
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                Text(car.hint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(pal.hint)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - 選配清單

private struct VehicleResaleCatalogSection: View {
    let report: VehicleResaleReport
    let onEdit: () -> Void
    let onTemplates: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "選配清單", trailing: report.catalogTrailing,
                              addLabel: "編輯選配清單", onAdd: onEdit)
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onEdit) {
                    listBody(pal)
                }
                .buttonStyle(MoneyPressStyle())
                .accessibilityHint("點兩下編輯選配清單")
                Divider().padding(.leading, 14)
                actions(pal)
            }
            .modifier(FinanceCardChrome())
        }
    }

    @ViewBuilder
    private func listBody(_ pal: TripBoardPalette) -> some View {
        if report.catalog.isEmpty {
            Text(report.catalogEmptyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(report.catalog.enumerated()), id: \.element.id) { i, row in
                    if i > 0 {
                        Divider().padding(.leading, 14)
                    }
                    VehicleResaleOptionRowView(row: row, pal: pal)
                }
            }
            .contentShape(Rectangle())
        }
    }

    /// 兩顆膠囊是 fixedSize：大字級、小螢幕放不下一排時改成上下兩排（不然會超出白卡）
    private func actions(_ pal: TripBoardPalette) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                pills(pal)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                pills(pal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func pills(_ pal: TripBoardPalette) -> some View {
        VehicleResalePillButton(title: "帶入常見選配", icon: "list.bullet.rectangle", pal: pal,
                                action: onTemplates)
        VehicleResalePillButton(title: "編輯清單", icon: "pencil", pal: pal, action: onEdit)
    }
}

/// 選配一列：名稱（下面灰字誰勾了）、右邊原價或「沒填價格」
private struct VehicleResaleOptionRowView: View {
    let row: VehicleResaleReport.OptionRow
    let pal: TripBoardPalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.usage.isEmpty {
                    Text(row.usage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            price
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var price: some View {
        if row.priceMissing {
            FinanceMiniTag(text: row.priceText, color: MoneyTone.warn.color(pal))
        } else {
            // 金額不折行：大字級時先縮字、名稱那欄去折行
            Text(row.priceText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }
}

/// 白卡裡的小膠囊按鈕（「帶入常見選配」「編輯清單」）
private struct VehicleResalePillButton: View {
    let title: String
    let icon: String
    let pal: TripBoardPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(pal.hint)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .frame(minHeight: 30)
                .background(pal.hint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(MoneyPressStyle())
    }
}

// MARK: - 市場上看到的車

private struct VehicleResaleListingsSection: View {
    let report: VehicleResaleReport
    let onAdd: () -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (VehicleResaleReport.Listing) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceCardHeader(title: "市場上看到的車", trailing: report.listingsTrailing,
                              addLabel: "加一台市場上的車", onAdd: onAdd)
            if report.listings.isEmpty {
                VehicleResaleAddCard(text: "＋ 加一台市場上看到的車（8891、臉書社團、車商網站都可以）", action: onAdd)
            } else {
                ForEach(report.listings) { item in
                    VehicleResaleListingCard(item: item, onEdit: { onEdit(item.id) }, onDelete: { onDelete(item) })
                }
            }
        }
    }
}

/// 一整列都是按鈕的白卡（還沒有任何一台時）
private struct VehicleResaleAddCard: View {
    let text: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TripBoardPalette(scheme).hint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(Rectangle())
            .modifier(FinanceCardChrome())
        }
        .buttonStyle(MoneyPressStyle())
    }
}

/// 市場上的一台：標題列（網頁、⋯ 選單）在按鈕外面；下面整塊點了編輯
private struct VehicleResaleListingCard: View {
    let item: VehicleResaleReport.Listing
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = TripBoardPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            titleRow(pal)
            Button(action: onEdit) {
                details(pal)
            }
            .buttonStyle(MoneyPressStyle())
            .accessibilityHint("點兩下編輯這台")
        }
        .modifier(FinanceCardChrome())
    }

    private func titleRow(_ pal: TripBoardPalette) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            linkButton(pal)
            menu(pal)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func linkButton(_ pal: TripBoardPalette) -> some View {
        if let url = item.link {
            Link(destination: url) {
                Label("網頁", systemImage: "safari")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pal.hint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(pal.hint.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("用 Safari 打開這台的網頁")
        }
    }

    private func menu(_ pal: TripBoardPalette) -> some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("編輯", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("刪除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(pal.label)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("這台的選項")
    }

    private func details(_ pal: TripBoardPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VehicleResaleRows(rows: item.rows)
            stepsBlock(pal)
            optionsBlock(pal)
            problemRow(pal)
            noteRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stepsBlock(_ pal: TripBoardPalette) -> some View {
        if !item.steps.isEmpty {
            Divider().padding(.leading, 14)
            VStack(alignment: .leading, spacing: 5) {
                Text("怎麼調成你的車")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(pal.label)
                ForEach(Array(item.steps.enumerated()), id: \.offset) { _, step in
                    Text(step)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func optionsBlock(_ pal: TripBoardPalette) -> some View {
        if !item.optionLines.isEmpty {
            Divider().padding(.leading, 14)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.optionLines) { line in
                    optionLine(line, pal: pal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func optionLine(_ line: VehicleResaleReport.OptionLine, pal: TripBoardPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: Self.icon(line.kind))
                .foregroundStyle(Self.tone(line.kind).color(pal))
            Text(line.text)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private static func icon(_ k: VehicleResaleReport.OptionLine.Kind) -> String {
        switch k {
        case .missing: return "minus.circle.fill"
        case .extra: return "plus.circle.fill"
        case .same: return "checkmark.circle.fill"
        }
    }

    private static func tone(_ k: VehicleResaleReport.OptionLine.Kind) -> MoneyTone {
        switch k {
        case .missing: return .warn
        case .extra: return .neutral
        case .same: return .good
        }
    }

    @ViewBuilder
    private func problemRow(_ pal: TripBoardPalette) -> some View {
        if let p = item.problem {
            Divider().padding(.leading, 14)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(p)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MoneyTone.warn.color(pal))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var noteRow: some View {
        if !item.note.isEmpty {
            Divider().padding(.leading, 14)
            Text(item.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - 共用的列

/// 一串「左標籤、右值」的列，列和列之間細線（同車輛資料卡）
private struct VehicleResaleRows: View {
    let rows: [VehicleResaleReport.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 {
                    Divider().padding(.leading, 14)
                }
                VehicleResaleRowView(row: r)
            }
        }
    }
}

private struct VehicleResaleRowView: View {
    let row: VehicleResaleReport.Row

    var body: some View {
        FinanceInfoRow(label: row.label, value: valueText, labelWidth: 104)
    }

    /// 值；下面接一行灰字（細字用 String 給 Text，不走 LocalizedStringKey，「52.8%」的 % 不會被當格式）
    private var valueText: Text {
        let weight: Font.Weight = row.strong ? .heavy : .semibold
        let main = Text(row.value).fontWeight(weight)
        guard let detail = row.detail else { return main }
        let note = Text(detail).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
        return Text("\(main)\n\(note)")
    }
}

/// 頁面最下面「怎麼算的」
private struct VehicleResaleFootnote: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("怎麼算的")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(verbatim: "\(i + 1). \(line)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

// MARK: - 輸入框的字 ↔ 數字

private enum VehicleResaleInput {
    /// 「398」「15.2」萬 → 元；空白、看不懂、≤ 0 回 nil
    static func wan(_ text: String) -> Double? {
        guard let w = Double(text.trimmingCharacters(in: .whitespaces)), w.isFinite, w > 0 else { return nil }
        return w * 10_000
    }

    /// 公里：空白、看不懂、≤ 0 回 nil
    static func positive(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// 元 → 帶回輸入框的萬（4 位小數＝1 元精度，去掉多餘的 0；同 AddVehicleView.editableAmountText）
    static func wanText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        var text = String(format: "%.4f", value / 10_000)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    static func kmText(_ km: Double?) -> String {
        guard let km, km > 0 else { return "" }
        return String(format: "%.0f", km.rounded())
    }

    /// 年份選單：今年＋1 往回 30 年；選中的年份不在裡面就補進去
    static func years(including selected: Int) -> [Int] {
        let now = VehicleResaleText.calendar.component(.year, from: Date())
        var list: [Int] = Array(((now - 30)...(now + 1)).reversed())
        if selected > 0, !list.contains(selected) {
            list.append(selected)
            list.sort(by: >)
        }
        return list
    }

    /// 清單編輯頁的列 → 選配（名稱和原價都空白的列丟掉；只有原價的叫「未命名選配」）。
    /// keep：有車勾著的選配，就算名稱和原價都被清空也留著（叫「未命名選配」）：
    /// 要刪有車勾的選配一律走左滑＋確認框，不能清空欄位就默默刪掉、連勾選一起不見
    static func options(_ drafts: [VehicleResaleOptionDraft], keep: Set<UUID>) -> [VehicleResaleOption] {
        var out: [VehicleResaleOption] = []
        for d in drafts {
            let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let price = wan(d.priceText)
            if name.isEmpty && price == nil && !keep.contains(d.id) { continue }
            out.append(VehicleResaleOption(id: d.id, name: name.isEmpty ? "未命名選配" : name, price: price))
        }
        return out
    }

    static func odometerLabel(_ r: VehicleOdometer.Reading) -> String {
        "記帳裡最近的里程 " + VehicleResaleText.km(r.km) + "（" + VehicleResaleText.ymd(r.date) + "）帶入"
    }
}

/// 清單編輯頁的一列（原價是輸入框的字）
private struct VehicleResaleOptionDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var priceText: String

    init(id: UUID = UUID(), name: String = "", priceText: String = "") {
        self.id = id
        self.name = name
        self.priceText = priceText
    }

    init(_ option: VehicleResaleOption) {
        self.init(id: option.id, name: option.name, priceText: VehicleResaleInput.wanText(option.price))
    }
}

// MARK: - 打勾選配（我的車、市場上的車共用）

/// 打勾那一區的狀態：共用清單（打開時的樣子）＋這次新加的＋勾了哪些
private struct VehicleResaleOptionPicker: Equatable {
    let catalog: [VehicleResaleOption]
    var added: [VehicleResaleOption] = []
    var checked: Set<UUID>
    var newName = ""
    var newPriceText = ""

    init(catalog: [VehicleResaleOption], checked ids: [UUID]) {
        self.catalog = catalog
        let valid = Set(catalog.map(\.id))
        checked = Set(ids.filter { valid.contains($0) })
    }

    var all: [VehicleResaleOption] { catalog + added }

    /// 存檔用：照清單順序（先原本的、再新加的）
    var checkedIds: [UUID] {
        all.filter { checked.contains($0.id) }.map(\.id)
    }

    var checkedTotal: Double {
        var sum = 0.0
        for o in all where checked.contains(o.id) {
            sum += max(0, o.price ?? 0)
        }
        return sum
    }

    var checkedUnpriced: Int {
        all.filter { checked.contains($0.id) && VehicleResaleMath.positive($0.price) == nil }.count
    }

    /// 清單上還在的那幾個 id
    func valid(_ ids: [UUID]) -> [UUID] {
        let set = Set(all.map(\.id))
        return ids.filter { set.contains($0) }
    }

    mutating func toggle(_ id: UUID) {
        if checked.contains(id) {
            checked.remove(id)
        } else {
            checked.insert(id)
        }
    }

    mutating func sameAs(_ ids: [UUID]) {
        checked = Set(valid(ids))
    }

    /// 「加進選配清單並勾起來」：同名的已經在清單上就直接勾那一項，不重複加
    mutating func addNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let key = VehicleResaleMath.key(name)
        if let same = all.first(where: { VehicleResaleMath.key($0.name) == key }) {
            checked.insert(same.id)
        } else {
            let o = VehicleResaleOption(name: name, price: VehicleResaleInput.wan(newPriceText))
            added.append(o)
            checked.insert(o.id)
        }
        newName = ""
        newPriceText = ""
    }
}

/// 打勾的一列：圓圈勾、名稱、右邊原價（沒填價格橘字）
private struct VehicleResaleCheckRow: View {
    let option: VehicleResaleOption
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Color(tb: 0x1F9D57) : Color.secondary)
                Text(option.name)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                priceText
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private var priceText: some View {
        let missing = VehicleResaleMath.positive(option.price) == nil
        return Text(VehicleResaleText.optionPrice(option.price))
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(missing ? Color.orange : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .layoutPriority(1)
    }
}

/// 編輯頁裡的兩個 Section：整份清單一列一列打勾、清單上沒有的直接加
private struct VehicleResaleOptionSections: View {
    @Binding var picker: VehicleResaleOptionPicker
    /// 市場上的車才有「跟我的車一樣」（我的車勾的 id）；我的車自己傳 nil
    let sameAsMine: [UUID]?

    var body: some View {
        checklist
        addSection
    }

    private var checklist: some View {
        Section {
            sameButton
            if picker.all.isEmpty {
                Text("選配清單還是空的：在下面加，或回估價頁按「帶入常見選配」。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(picker.all) { o in
                VehicleResaleCheckRow(option: o, checked: picker.checked.contains(o.id)) {
                    picker.toggle(o.id)
                }
            }
        } header: {
            Text("選配")
        } footer: {
            Text(footerText)
        }
    }

    @ViewBuilder
    private var sameButton: some View {
        if let mine = sameAsMine {
            let ids = picker.valid(mine)
            if !ids.isEmpty {
                Button {
                    picker.sameAs(ids)
                } label: {
                    Label(Self.sameTitle(ids.count), systemImage: "equal.circle")
                }
            }
        }
    }

    private static func sameTitle(_ n: Int) -> String {
        "跟我的車一樣（勾 \(n) 項，再微調）"
    }

    private var footerText: String {
        let n = picker.checked.count
        guard n > 0 else { return "勾這台有的選配。清單上沒有的，在下面加。" }
        var s = "勾了 \(n) 項，原價合計 " + VehicleResaleText.money(picker.checkedTotal)
        let unpriced = picker.checkedUnpriced
        if unpriced > 0 { s += "（\(unpriced) 項沒填價格，先算 0）" }
        return s + "。"
    }

    private var addSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("選配名稱", text: $picker.newName)
                TextField("原價", text: $picker.newPriceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                Text("萬").foregroundStyle(.secondary)
            }
            Button {
                picker.addNew()
            } label: {
                Label("加進選配清單並勾起來", systemImage: "plus.circle.fill")
            }
            .disabled(picker.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("清單上沒有的選配")
        } footer: {
            Text("會加進共用的選配清單，其他台車也能勾。原價不知道可以先空著（算 0）。")
        }
    }
}

/// 「12」萬、「35000」公里這種一列：左邊標題、右邊輸入框＋單位
private struct VehicleResaleAmountField: View {
    let title: String
    @Binding var text: String
    let unit: String
    let decimal: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            TextField("沒填", text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 編輯：我的車

private struct VehicleResaleMyCarEdit {
    let builtYear: Int
    let builtMonth: Int
    let newPrice: Double?
    let mileageKm: Double?
    let optionIds: [UUID]
    let added: [VehicleResaleOption]
}

private struct VehicleResaleMyCarForm: Equatable {
    var year: Int
    var month: Int
    var priceText: String
    var kmText: String
    var picker: VehicleResaleOptionPicker

    init(start ws: VehicleResaleWorkspace) {
        let thisYear = VehicleResaleText.calendar.component(.year, from: Date())
        year = ws.builtYear ?? thisYear
        month = min(12, max(1, ws.builtMonth ?? 1))
        priceText = VehicleResaleInput.wanText(ws.newPrice)
        kmText = VehicleResaleInput.kmText(ws.mileageKm)
        picker = VehicleResaleOptionPicker(catalog: ws.options, checked: ws.myOptionIds)
    }
}

private struct VehicleResaleMyCarEditor: View {
    @Environment(\.dismiss) private var dismiss

    let vehicleName: String
    let odometer: VehicleOdometer.Reading?
    let onSave: (VehicleResaleMyCarEdit) -> Void
    private let initial: VehicleResaleMyCarForm

    @State private var form: VehicleResaleMyCarForm
    @State private var isSaving = false

    init(vehicleName: String, start: VehicleResaleWorkspace, odometer: VehicleOdometer.Reading?,
         onSave: @escaping (VehicleResaleMyCarEdit) -> Void) {
        self.vehicleName = vehicleName
        self.odometer = odometer
        self.onSave = onSave
        let f = VehicleResaleMyCarForm(start: start)
        initial = f
        _form = State(initialValue: f)
    }

    var body: some View {
        NavigationStack {
            Form {
                carSection
                VehicleResaleOptionSections(picker: $form.picker, sameAsMine: nil)
            }
            .navigationTitle("我的車")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        // 有改過時只能按「取消」或「儲存」，免得一滑就丟掉剛勾的
        .interactiveDismissDisabled(form != initial)
    }

    private var carSection: some View {
        Section {
            LabeledContent("車子", value: vehicleName)
            Picker("出廠／領牌年", selection: $form.year) {
                ForEach(VehicleResaleInput.years(including: form.year), id: \.self) { y in
                    Text(verbatim: "\(y) 年").tag(y)
                }
            }
            Picker("月份", selection: $form.month) {
                ForEach(1...12, id: \.self) { m in
                    Text(verbatim: "\(m) 月").tag(m)
                }
            }
            VehicleResaleAmountField(title: "新車原價（不含選配）", text: $form.priceText, unit: "萬元", decimal: true)
            VehicleResaleAmountField(title: "目前里程", text: $form.kmText, unit: "公里", decimal: false)
            odometerButton
        } header: {
            Text("我的車")
        } footer: {
            Text("一開始用車輛資料帶入：購入日當出廠年月、購入價當新車原價。購入價如果已經含選配，這裡改成不含選配的牌價，選配在下面勾。金額以萬元輸入，例如 400 代表 NT$4,000,000。")
        }
    }

    @ViewBuilder
    private var odometerButton: some View {
        if let o = odometer, VehicleResaleInput.positive(form.kmText) != o.km.rounded() {
            Button {
                form.kmText = VehicleResaleInput.kmText(o.km)
            } label: {
                Label(VehicleResaleInput.odometerLabel(o), systemImage: "speedometer")
                    .font(.caption)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("儲存") { save() }
                .bold()
                .disabled(isSaving)
        }
    }

    /// 先關頁、下一個 runloop 才交給估價頁寫 store；名稱打了還沒按「加進清單」的也一起加
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        var f = form
        f.picker.addNew()
        let edit = VehicleResaleMyCarEdit(builtYear: f.year, builtMonth: f.month,
                                          newPrice: VehicleResaleInput.wan(f.priceText),
                                          mileageKm: VehicleResaleInput.positive(f.kmText),
                                          optionIds: f.picker.checkedIds, added: f.picker.added)
        let done = onSave
        dismiss()
        DispatchQueue.main.async { done(edit) }
    }
}

// MARK: - 編輯：市場上的一台

private struct VehicleResaleListingForm: Equatable {
    var title: String
    var link: String
    /// 0＝沒填
    var year: Int
    /// 0＝不知道（當 VehicleResaleMath.unknownMonth 月）
    var month: Int
    var kmText: String
    var newPriceText: String
    var askingText: String
    var seenDate: Date
    var note: String
    var picker: VehicleResaleOptionPicker

    init(listing l: VehicleResaleListing?, catalog: [VehicleResaleOption]) {
        title = l?.title ?? ""
        link = l?.link ?? ""
        year = l?.builtYear ?? 0
        month = l?.builtMonth ?? 0
        kmText = VehicleResaleInput.kmText(l?.mileageKm)
        newPriceText = VehicleResaleInput.wanText(l?.newPrice)
        askingText = VehicleResaleInput.wanText(l?.askingPrice)
        // 新的一台用今天 0 點：父頁重畫時 init 會再跑一次、initial 跟著重算，用 Date() 會差幾毫秒，
        // form != initial 變 true，什麼都沒改也滑不掉
        seenDate = l?.seenDate ?? VehicleResaleText.calendar.startOfDay(for: Date())
        note = l?.note ?? ""
        picker = VehicleResaleOptionPicker(catalog: catalog, checked: l?.optionIds ?? [])
    }

    /// 新的一台什麼都還沒填（儲存鈕先不給按）
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && VehicleResaleInput.wan(askingText) == nil && VehicleResaleInput.wan(newPriceText) == nil
    }
}

private struct VehicleResaleListingEditor: View {
    @Environment(\.dismiss) private var dismiss

    let editingId: UUID?
    let myOptionIds: [UUID]
    let onSave: (VehicleResaleListing, [VehicleResaleOption]) -> Void
    let onDelete: (UUID) -> Void
    private let initial: VehicleResaleListingForm

    @State private var form: VehicleResaleListingForm
    @State private var askDelete = false
    @State private var isSaving = false

    init(editing: VehicleResaleListing?, catalog: [VehicleResaleOption], myOptionIds: [UUID],
         onSave: @escaping (VehicleResaleListing, [VehicleResaleOption]) -> Void,
         onDelete: @escaping (UUID) -> Void) {
        editingId = editing?.id
        self.myOptionIds = myOptionIds
        self.onSave = onSave
        self.onDelete = onDelete
        let f = VehicleResaleListingForm(listing: editing, catalog: catalog)
        initial = f
        _form = State(initialValue: f)
    }

    var body: some View {
        NavigationStack {
            Form {
                carSection
                yearSection
                priceSection
                VehicleResaleOptionSections(picker: $form.picker, sameAsMine: myOptionIds)
                otherSection
                deleteSection
            }
            .navigationTitle(editingId == nil ? "加一台市場上的車" : "編輯這台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert("刪除這台？", isPresented: $askDelete) {
                Button("刪除", role: .destructive) { deleteTapped() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這台的資料會刪掉，估價會重算。")
            }
        }
        .interactiveDismissDisabled(form != initial)
    }

    private var carSection: some View {
        Section {
            TextField("標題或來源（例：8891・2022 Taycan 4S）", text: $form.title)
            TextField("網址（選填，存了就能從估價頁打開）", text: $form.link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("這台車")
        }
    }

    private var yearSection: some View {
        Section {
            Picker("出廠年", selection: $form.year) {
                Text("沒填").tag(0)
                ForEach(VehicleResaleInput.years(including: form.year), id: \.self) { y in
                    Text(verbatim: "\(y) 年").tag(y)
                }
            }
            if form.year > 0 {
                monthPicker
            }
            VehicleResaleAmountField(title: "里程", text: $form.kmText, unit: "公里", decimal: false)
        } header: {
            Text("年份與里程")
        } footer: {
            Text("出廠年月或領牌年月都可以，跟「我的車」用同一種就好。")
        }
    }

    private var monthPicker: some View {
        Picker("月份", selection: $form.month) {
            Text(verbatim: "不知道（當 \(VehicleResaleMath.unknownMonth) 月）").tag(0)
            ForEach(1...12, id: \.self) { m in
                Text(verbatim: "\(m) 月").tag(m)
            }
        }
    }

    private var priceSection: some View {
        Section {
            VehicleResaleAmountField(title: "新車原價（不含選配）", text: $form.newPriceText, unit: "萬元", decimal: true)
            VehicleResaleAmountField(title: "二手標價", text: $form.askingText, unit: "萬元", decimal: true)
        } header: {
            Text("價格")
        } footer: {
            Text("以萬元輸入，例如 398 代表 NT$3,980,000。新車原價可以查那一年的價目表。")
        }
    }

    private var otherSection: some View {
        Section {
            DatePicker("看到的日期", selection: $form.seenDate, displayedComponents: .date)
            TextField("備註（例：原廠保固到 2027/3、右後輪框有刮傷）", text: $form.note, axis: .vertical)
                .lineLimit(3)
        } header: {
            Text("其他")
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if editingId != nil {
            Section {
                Button(role: .destructive) {
                    askDelete = true
                } label: {
                    Label("刪除這台", systemImage: "trash")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("儲存") { save() }
                .bold()
                .disabled(isSaving || form.isBlank)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        var f = form
        f.picker.addNew()
        let listing = VehicleResaleListing(
            id: editingId ?? UUID(),
            title: f.title.trimmingCharacters(in: .whitespacesAndNewlines),
            link: f.link.trimmingCharacters(in: .whitespacesAndNewlines),
            builtYear: f.year > 0 ? f.year : nil,
            builtMonth: (f.year > 0 && f.month > 0) ? f.month : nil,
            mileageKm: VehicleResaleInput.positive(f.kmText),
            newPrice: VehicleResaleInput.wan(f.newPriceText),
            optionIds: f.picker.checkedIds,
            askingPrice: VehicleResaleInput.wan(f.askingText),
            seenDate: f.seenDate,
            note: f.note.trimmingCharacters(in: .whitespacesAndNewlines))
        let added = f.picker.added
        let done = onSave
        dismiss()
        DispatchQueue.main.async { done(listing, added) }
    }

    private func deleteTapped() {
        guard let id = editingId else { return }
        let done = onDelete
        dismiss()
        DispatchQueue.main.async { done(id) }
    }
}

// MARK: - 編輯：選配清單

private struct VehicleResaleCatalogEditor: View {
    @Environment(\.dismiss) private var dismiss

    let usage: [UUID: VehicleResaleMath.Usage]
    let onSave: ([VehicleResaleOption]) -> Void
    private let initial: [VehicleResaleOptionDraft]

    @State private var drafts: [VehicleResaleOptionDraft]
    @State private var pendingDelete: VehicleResaleOptionDraft?
    @State private var isSaving = false

    init(options: [VehicleResaleOption], usage: [UUID: VehicleResaleMath.Usage],
         onSave: @escaping ([VehicleResaleOption]) -> Void) {
        self.usage = usage
        self.onSave = onSave
        let list = options.map { VehicleResaleOptionDraft($0) }
        initial = list
        _drafts = State(initialValue: list)
    }

    var body: some View {
        NavigationStack {
            Form {
                listSection
            }
            .navigationTitle("選配清單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .alert(deleteTitle, isPresented: deleteShown, presenting: pendingDelete) { d in
                Button("刪除", role: .destructive) { remove(d.id) }
                Button("取消", role: .cancel) {}
            } message: { d in
                Text(deleteMessage(d))
            }
        }
        .interactiveDismissDisabled(drafts != initial)
    }

    private var listSection: some View {
        Section {
            ForEach($drafts) { $d in
                VehicleResaleOptionEditRow(option: $d)
            }
            .onDelete { offsets in askDelete(offsets) }
            Button {
                drafts.append(VehicleResaleOptionDraft())
            } label: {
                Label("加一個選配", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("共用的選配清單")
        } footer: {
            Text("左滑可以刪除。原價以萬元輸入，例如 12 代表 NT$120,000；不知道可以先空著（算 0）。我的車和市場上的車都從這份清單打勾。")
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("儲存") { save() }
                .bold()
                .disabled(isSaving)
        }
    }

    /// 沒有車勾的直接拿掉；有車勾的先問（左滑一次只會有一列）
    private func askDelete(_ offsets: IndexSet) {
        let targets = offsets.map { drafts[$0] }
        let unused = Set(targets.filter { (usage[$0.id]?.total ?? 0) == 0 }.map(\.id))
        drafts.removeAll { unused.contains($0.id) }
        if let used = targets.first(where: { (usage[$0.id]?.total ?? 0) > 0 }) {
            pendingDelete = used
        }
    }

    private func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteTitle: String {
        guard let d = pendingDelete else { return "" }
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "刪除「\(name.isEmpty ? "未命名選配" : name)」？"
    }

    private func deleteMessage(_ d: VehicleResaleOptionDraft) -> String {
        let who = VehicleResaleText.who(usage[d.id])
        return "\(who)勾了這個選配。刪掉之後這些車都不算它，估價會重算（按「儲存」才會真的刪）。"
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let used = Set(usage.compactMap { $0.value.total > 0 ? $0.key : nil })
        let list = VehicleResaleInput.options(drafts, keep: used)
        let done = onSave
        dismiss()
        DispatchQueue.main.async { done(list) }
    }
}

/// 清單編輯頁的一列：名稱、原價（萬）
private struct VehicleResaleOptionEditRow: View {
    @Binding var option: VehicleResaleOptionDraft

    var body: some View {
        HStack(spacing: 8) {
            TextField("選配名稱", text: $option.name)
            TextField("沒填", text: $option.priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 76)
            Text("萬")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 帶入常見選配（品牌範本）

private struct VehicleResaleTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 清單上已經有的名稱（VehicleResaleMath.key）
    let existing: Set<String>
    let guessed: VehicleOptionBrand?
    let onAdd: ([String]) -> Void

    @State private var brand: VehicleOptionBrand?
    @State private var picked: Set<String> = []
    @State private var isSaving = false

    init(existing: Set<String>, guessed: VehicleOptionBrand?, onAdd: @escaping ([String]) -> Void) {
        self.existing = existing
        self.guessed = guessed
        self.onAdd = onAdd
        _brand = State(initialValue: guessed)
    }

    var body: some View {
        NavigationStack {
            Form {
                brandSection
                namesSection
            }
            .navigationTitle("帶入常見選配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .onChange(of: brand) { _, _ in picked = [] }
        }
        // 勾了還沒按「加入」時只能按「取消」或「加入」，免得一滑就丟掉剛勾的
        .interactiveDismissDisabled(!picked.isEmpty)
    }

    private var brandSection: some View {
        Section {
            Picker("品牌", selection: $brand) {
                ForEach(VehicleOptionBrand.allCases) { b in
                    Text(b.rawValue).tag(Optional(b))
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(brandFooter)
        }
    }

    private var brandFooter: String {
        if let g = guessed { return "照車輛資料判斷是\(g.rawValue)，不對可以換。" }
        return "車輛資料看不出是哪個品牌，先選一個。"
    }

    @ViewBuilder
    private var namesSection: some View {
        if let b = brand {
            Section {
                pickAllButton(b)
                ForEach(VehicleOptionTemplates.brand(b), id: \.self) { name in
                    row(name)
                }
            } header: {
                Text(verbatim: "\(b.rawValue) 常見選配")
            } footer: {
                Text("只帶入名稱，原價空白（算 0）；加進清單之後，再到「編輯清單」填上你查到的原價。")
            }
        }
    }

    /// 還沒在清單上的全部勾起來
    private func pickAllButton(_ b: VehicleOptionBrand) -> some View {
        let available = VehicleOptionTemplates.brand(b).filter { !isExisting($0) }
        return Button {
            picked = Set(available)
        } label: {
            Label("全部勾起來", systemImage: "checklist")
        }
        .disabled(available.isEmpty || picked.count == available.count)
    }

    private func isExisting(_ name: String) -> Bool {
        existing.contains(VehicleResaleMath.key(name))
    }

    private func row(_ name: String) -> some View {
        let already = isExisting(name)
        let on = picked.contains(name)
        return Button {
            toggle(name)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: already || on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(Self.markColor(already: already, on: on))
                Text(name)
                    .foregroundStyle(already ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if already {
                    Text("已在清單")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(already)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private static func markColor(already: Bool, on: Bool) -> Color {
        if already { return Color.secondary }
        return on ? Color(tb: 0x1F9D57) : Color.secondary
    }

    private func toggle(_ name: String) {
        if picked.contains(name) {
            picked.remove(name)
        } else {
            picked.insert(name)
        }
    }

    private var addTitle: String {
        picked.isEmpty ? "加入" : "加入 \(picked.count) 項"
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(addTitle) { add() }
                .bold()
                .disabled(picked.isEmpty || isSaving)
        }
    }

    /// 照範本的順序加（不照勾的順序）
    private func add() {
        guard let b = brand, !isSaving else { return }
        isSaving = true
        let names = VehicleOptionTemplates.brand(b).filter { picked.contains($0) }
        let done = onAdd
        dismiss()
        DispatchQueue.main.async { done(names) }
    }
}
