import SwiftUI
import Charts

// MARK: - 收支項目詳情卡片標準模組
//
// 收入與變動支出的項目點開先看卡片（固定支出已有領域專屬的 FixedExpenseCard，
// 含儲蓄險/貸款甘特圖，維持原樣）；兩種入口共用這一個元件，
// 依 target 決定資料來源與欄位。右上可匯出圖片／文字分享，「編輯」才進編輯表單。
// 備註支援就地編輯（InlineEditBlock）；變動支出含帳單照片區。
// 匯出圖片為靜態分享版（無鉛筆鈕、空欄位不顯示、含匯出戳記；照片不入圖）。

enum FinanceCardTarget: Identifiable {
    case income(UUID)
    case variableExpense(UUID)
    var id: UUID {
        switch self {
        case .income(let i), .variableExpense(let i): return i
        }
    }
}

struct FinanceCardSharePayload: Identifiable { let id = UUID(); let items: [Any] }

struct FinanceItemCard: View {
    let target: FinanceCardTarget

    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var financeStore: FinanceStore
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var shareItem: FinanceCardSharePayload?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()
    private static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f
    }()
    private static let displayStampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private static let decimalFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    // MARK: 資料（一律現查 store，編輯儲存後即時反映）

    private var income: Income? {
        guard case .income(let id) = target else { return nil }
        return store.incomes.first { $0.id == id }
    }
    private var expense: Expense? {
        guard case .variableExpense(let id) = target else { return nil }
        return store.expenses.first { $0.id == id }
    }
    private var exists: Bool { income != nil || expense != nil }

    private var isIncome: Bool { if case .income = target { return true }; return false }
    private var accent: Color { isIncome ? .green : .orange }
    private var navTitle: String { isIncome ? "收入" : "變動支出" }
    private var icon: String {
        if let inc = income { return inc.category.icon }
        return expense?.variableCategory?.icon ?? "cart.fill"
    }
    private var titleText: String {
        let t = income?.title ?? expense?.title ?? ""
        return t.isEmpty ? "未命名項目" : t
    }

    /// 金額顯示：外幣附幣別；台幣走萬/億智慧量級
    private var amountText: String {
        if let inc = income { return inc.amount.ntdWanString }
        guard let e = expense else { return "" }
        let code = e.currencyCode
        if code != "NT$" && code != "TWD" && !code.isEmpty {
            let display: Double
            if let rate = store.currencyRates.first(where: { $0.code == code }), rate.rate > 0 {
                display = e.amount / rate.rate
            } else {
                display = e.amount
            }
            let s = Self.decimalFmt.string(from: NSNumber(value: display)) ?? "0"
            return "\(code) \(s)（≈ \(e.amount.ntdWanString)）"
        }
        return e.amount.ntdWanString
    }

    private var categoryText: String {
        if let inc = income { return inc.category.rawValue }
        return expense?.variableCategory?.rawValue ?? "未分類"
    }

    /// 扣款／入帳目標（銀行或信用卡）
    private var accountLabel: String? {
        if let e = expense {
            if let cardId = e.linkedCreditCardMilestoneId,
               let card = lifeStore.milestones.first(where: { $0.id == cardId }) {
                return card.cardName ?? card.title
            }
            if let bankId = e.linkedBankMilestoneId,
               let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
                let name = ms.bankName ?? ms.title
                let currency = e.linkedBankCurrency ?? "NT$"
                return currency == "NT$" ? name : "\(name) · \(currency)"
            }
            return nil
        }
        if let inc = income, let bankId = inc.linkedBankMilestoneId,
           let ms = lifeStore.milestones.first(where: { $0.id == bankId }) {
            let name = ms.bankName ?? ms.title
            let currency = inc.linkedBankCurrency ?? "NT$"
            return currency == "NT$" ? name : "\(name) · \(currency)"
        }
        return nil
    }

    private var noteText: String { income?.note ?? expense?.note ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if exists {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            cardBody(forExport: false)
                            if let e = expense { photoSection(e) }
                        }
                        .padding()
                    }
                } else {
                    // 在編輯表單裡被刪除 → 自動關閉卡片
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            let photoCount = expense?.photoFileNames.count ?? 0
                            Button { shareJPG() } label: {
                                Label(photoCount > 0 ? "匯出圖片（含帳單照片 \(photoCount) 張）" : "匯出圖片",
                                      systemImage: "photo")
                            }
                            if photoCount > 0 {
                                Button { sharePhotosOnly() } label: {
                                    Label("只匯出帳單照片（\(photoCount) 張）", systemImage: "photo.stack")
                                }
                            }
                            Button { shareText() } label: { Label("匯出文字", systemImage: "text.alignleft") }
                        } label: { Image(systemName: "square.and.arrow.up") }
                        Button("編輯") { showEdit = true }.bold().foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showEdit) { editorSheet }
            .sheet(item: $shareItem) { item in ShareSheet(items: item.items) }
        }
    }

    @ViewBuilder
    private var editorSheet: some View {
        if let inc = income {
            AddIncomeView(editing: inc)
        } else if let e = expense {
            AddExpenseView(expenseType: .variable, editingExpense: e)
        }
    }

    // MARK: 卡片內容（畫面與匯出共用；forExport＝靜態分享版）

    @ViewBuilder
    private func cardBody(forExport: Bool) -> some View {
        titleBlock
        infoCard
        // [v25.328] 電動車充電支出：卡片顯示充電資訊與該車的每度電價走勢
        if let e = expense, isEVCharge(e) {
            evChargeBlock(e)
        }
        if forExport {
            if !noteText.isEmpty { staticNoteBlock }
            Text("美好人生・\(Self.displayStampFmt.string(from: Date())) 匯出")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            InlineEditBlock(title: "備註", text: noteText, accent: accent) { new in
                saveNote(new)
            }
        }
    }

    private var titleBlock: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text((isIncome ? "+" : "-") + amountText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isIncome ? Color.green : Color(red: 0.92, green: 0.28, blue: 0.28))
            }
            Spacer(minLength: 0)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            field("類別", categoryText)
            if let inc = income {
                Divider().padding(.leading, 14)
                field("週期", inc.period.rawValue)
                Divider().padding(.leading, 14)
                field("日期", Self.dateFmt.string(from: inc.date))
                if inc.isFixedSalary {
                    Divider().padding(.leading, 14)
                    field("固定薪水", inc.endDate.map {
                        "至 \(Self.dateFmt.string(from: $0))" + (inc.endReason.map { "（\($0.rawValue)）" } ?? "")
                    } ?? "持續計入")
                }
            }
            if let e = expense {
                Divider().padding(.leading, 14)
                field("日期", Self.dateFmt.string(from: e.date))
                if let member = e.diningMember, !member.isEmpty {
                    Divider().padding(.leading, 14)
                    field("同行成員", member)
                }
                if let recipient = e.socialRecipient, !recipient.isEmpty {
                    Divider().padding(.leading, 14)
                    field("社交對象", recipient)
                }
                if let addr = e.placeAddress, !addr.isEmpty {
                    Divider().padding(.leading, 14)
                    field("店家地址", addr)
                }
            }
            if let account = accountLabel {
                Divider().padding(.leading, 14)
                field(isIncome ? "入帳銀行" : "扣款目標", account)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var staticNoteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("備註").font(.caption).foregroundStyle(.secondary)
            Text(noteText).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 帳單照片（變動支出）：可拍照／從相簿新增，直接寫回並持久化
    private func photoSection(_ e: Expense) -> some View {
        MultiPhotoGallery(
            fileNames: Binding(
                get: { store.expenses.first { $0.id == e.id }?.photoFileNames ?? [] },
                set: { newNames in
                    guard var latest = store.expenses.first(where: { $0.id == e.id }) else { return }
                    latest.photoFileNames = newNames
                    store.update(latest)
                }
            ),
            urlFor: { Expense.photoURL(for: $0) },
            onSaveImage: { Expense.savePhoto($0, expenseId: e.id) },
            onDeleteFile: { Expense.deletePhoto($0) },
            onSavePDF: { Expense.savePDF($0, expenseId: e.id) },
            title: "帳單照片"
        )
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func saveNote(_ new: String) {
        if var inc = income {
            inc.note = new
            store.update(inc)
        } else if var e = expense {
            e.note = new
            store.update(e)
        }
    }

    // MARK: 分享

    @MainActor
    private func shareJPG() {
        guard exists else { return }
        let content = VStack(alignment: .leading, spacing: 16) { cardBody(forExport: true) }
            .frame(width: 420)
            .padding(20)
            .background(Color(.systemGroupedBackground))
            .environmentObject(store)
            .environmentObject(lifeStore)
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(UIScreen.main.scale, 3)
        guard let ui = renderer.uiImage, let data = ui.jpegData(compressionQuality: 0.95) else { return }
        let safeTitle = PagedImageExporter.sanitizeFileName(String(titleText.prefix(20)))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(navTitle)_\(safeTitle)_\(Self.stampFmt.string(from: Date())).jpg")
        do {
            try data.write(to: url)
            // 上傳過的帳單照片原檔一併附進分享（卡片圖 + 全部照片一次分享）
            var items: [Any] = [url]
            if let e = expense {
                for name in e.photoFileNames {
                    let photoURL = Expense.photoURL(for: name)
                    if FileManager.default.fileExists(atPath: photoURL.path) {
                        items.append(photoURL)
                    }
                }
            }
            shareItem = FinanceCardSharePayload(items: items)
        } catch { }
    }

    /// 只分享上傳的帳單照片原檔（不含卡片圖）
    private func sharePhotosOnly() {
        guard let e = expense else { return }
        let urls: [Any] = e.photoFileNames
            .map { Expense.photoURL(for: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        shareItem = FinanceCardSharePayload(items: urls)
    }

    private func shareText() {
        guard exists else { return }
        var lines: [String] = []
        lines.append("\(isIncome ? "💰 收入" : "🧾 變動支出")｜\(titleText)")
        lines.append("━━━━━━━━━━")
        lines.append("💵 金額：\((isIncome ? "+" : "-") + amountText)")
        lines.append("🏷 類別：\(categoryText)")
        if let inc = income {
            lines.append("🔁 週期：\(inc.period.rawValue)")
            lines.append("🗓 日期：\(Self.dateFmt.string(from: inc.date))")
            if inc.isFixedSalary {
                lines.append("📌 固定薪水：" + (inc.endDate.map { "至 \(Self.dateFmt.string(from: $0))" } ?? "持續計入"))
            }
        }
        if let e = expense {
            lines.append("🗓 日期：\(Self.dateFmt.string(from: e.date))")
            if let member = e.diningMember, !member.isEmpty { lines.append("👥 同行成員：\(member)") }
            if let recipient = e.socialRecipient, !recipient.isEmpty { lines.append("🎁 社交對象：\(recipient)") }
            if let addr = e.placeAddress, !addr.isEmpty { lines.append("📍 店家地址：\(addr)") }
        }
        if let account = accountLabel {
            lines.append("\(isIncome ? "🏦 入帳銀行" : "🏦 扣款目標")：\(account)")
        }
        if !noteText.isEmpty { lines.append(""); lines.append("💬 備註"); lines.append(noteText) }
        shareItem = FinanceCardSharePayload(items: [lines.joined(separator: "\n")])
    }
}

// MARK: - 電動車充電資訊區塊（v25.328）

extension FinanceItemCard {
    /// 這筆是「關聯汽車＋電費」且有填任何充電資料嗎
    func isEVCharge(_ e: Expense) -> Bool {
        e.vehicleExpenseCategory == .electricity && e.linkedVehicleId != nil
            && (e.evKwh != nil || e.evFromPct != nil || e.evToPct != nil || e.evOdometer != nil)
    }

    /// 充電資訊卡：度數／電量區間／里程錶／每度電價／本次推估容量，
    /// 下方附「這輛車」的每度電價走勢（本筆以大圓點標示）。畫面與匯出共用。
    @ViewBuilder
    func evChargeBlock(_ e: Expense) -> some View {
        let vehicleName = e.linkedVehicleId.flatMap { vid in
            financeStore.vehicles.first { $0.id == vid }?.name
        } ?? ""
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 16)
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
                Text("充電資訊" + (vehicleName.isEmpty ? "" : "・\(vehicleName)"))
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            VStack(spacing: 0) {
                if let kwh = e.evKwh {
                    evField("充電度數", String(format: "%g kWh", kwh))
                }
                if let f = e.evFromPct, let t = e.evToPct {
                    evField("電量", String(format: "%g%% → %g%%（+%g%%）", f, t, t - f))
                } else if let t = e.evToPct {
                    evField("充到電量", String(format: "%g%%", t))
                }
                if let odo = e.evOdometer {
                    evField("里程錶", String(format: "%g km", odo))
                }
                if let kwh = e.evKwh, kwh > 0 {
                    evField("每度電價", String(format: "NT$%.2f／kWh", e.amount / kwh))
                }
                if let kwh = e.evKwh, let f = e.evFromPct, let t = e.evToPct, t - f >= 15 {
                    evField("本次推估電池容量", String(format: "%.1f kWh", kwh / (t - f) * 100))
                }
            }

            // 這輛車的每度電價走勢（本筆大圓點）
            let sessions = evSessions(vehicleId: e.linkedVehicleId)
            if sessions.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("每度電價走勢（這輛車）")
                        .font(.caption).foregroundStyle(.secondary)
                    Chart(sessions) { se in
                        LineMark(x: .value("日期", se.date),
                                 y: .value("元/度", se.amount / (se.evKwh ?? 1)))
                            .foregroundStyle(.teal)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("日期", se.date),
                                  y: .value("元/度", se.amount / (se.evKwh ?? 1)))
                            .foregroundStyle(se.id == e.id ? Color.red : Color.teal)
                            .symbolSize(se.id == e.id ? 70 : 22)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 110)
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("本筆").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
            } else {
                Spacer().frame(height: 10)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func evField(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().padding(.leading, 14)
        }
    }

    /// 這輛車有填度數的充電紀錄（時間升冪）
    private func evSessions(vehicleId: UUID?) -> [Expense] {
        guard let vehicleId else { return [] }
        return store.expenses
            .filter { $0.linkedVehicleId == vehicleId
                && $0.vehicleExpenseCategory == .electricity
                && ($0.evKwh ?? 0) > 0 }
            .sorted { $0.date < $1.date }
    }
}
