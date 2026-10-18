import SwiftUI
import PhotosUI
import QuickLook
import ImageIO

// [v25.534] 房屋卡片用到的編輯頁與共用照片元件，從 RealEstateDetailView.swift 原封搬過來
// （卡片本身改成「資料＋各區 View＋外殼」之後，這些跟畫面無關的編輯頁獨立一個檔）。
// 搬家時只把 fileprivate 改成 internal：realEstateEditorSectionHeader、FloorItemEditTarget、FloorItemEditor。
// CutePhotoViewer、ThumbnailImageView、CutePhotoDraft 也給 VehicleDetailView 用；UtilityPaymentEditor、
// realEstateBankWithdrawalValue 也給 AddRealEstateView 用。

// MARK: - 編輯 sheet 共用 Section header
// 【美化 v9】ElevatorMaintenanceEditor／UtilityPaymentEditor 共用，4pt 漸層 Capsule 側條
// + 圖示 + 粗體標題，對齊全 App「表單 Section header 補齊」系列規格
// （ResumeView.AddMilestoneView／BusinessCardEditor／FamilyMembersResumeView 等既有做法）。
func realEstateEditorSectionHeader(_ title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 8) {
        Capsule()
            .fill(LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 14)
        Image(systemName: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

// MARK: - 電梯保養編輯

struct ElevatorMaintenanceEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: ElevatorMaintenance?

    @State private var date = Date()
    /// [v25.308] 多張照片：共用 MultiPhotoGallery 模組（拍照連拍/相簿多選/燈箱/刪除），
    /// 取代手刻的單張 PhotosPicker＋CameraPicker
    @State private var photoFileNames: [String] = []
    @State private var showDeleteConfirm = false
    // 儲存/刪除已 dismiss + 延後一個 runloop 才寫回 store，快速連點會讓兩次呼叫
    // 各自讀到同一份舊 estate 快照、後寫回者蓋掉先寫回者；比照 UtilityPaymentEditor
    // 既有修法補上忙碌守衛。
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("保養日期", selection: $date, displayedComponents: .date)

                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { ElevatorMaintenance.photoURL(for: $0) },
                        onSaveImage: { ElevatorMaintenance.savePhoto($0, id: UUID()) },
                        onDeleteFile: { ElevatorMaintenance.deletePhoto($0) },
                        title: "保養照片"
                    )
                    .padding(.vertical, 4)
                } header: {
                    realEstateEditorSectionHeader("保養記錄", icon: "wrench.and.screwdriver.fill", color: .teal)
                } footer: {
                    Text("可拍照連拍或從相簿多選（保養單、銘板、現場照）。")
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("刪除此記錄", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增保養記錄" : "編輯保養記錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // [v25.534] 這次新拍／新選的照片已經寫到磁碟、還沒存進紀錄，取消時刪掉，
                        // 不然會變成 iCloud 上一直重傳的孤兒檔（既有照片不動；照 UtilityPaymentEditor 的做法）
                        let original = Set(editing?.photoFileNames ?? [])
                        for name in photoFileNames where !original.contains(name) {
                            ElevatorMaintenance.deletePhoto(name)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold().foregroundStyle(.green).disabled(isSaving)
                }
            }
            .onAppear {
                if let e = editing {
                    date = e.date
                    photoFileNames = e.photoFileNames
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        isSaving = true
        let recordId = editing?.id ?? UUID()
        let record = ElevatorMaintenance(id: recordId, date: date, photoFileNames: photoFileNames)
        if let idx = estate.elevatorMaintenances.firstIndex(where: { $0.id == recordId }) {
            estate.elevatorMaintenances[idx] = record
        } else {
            estate.elevatorMaintenances.append(record)
        }
        // 先關閉 sheet，下一個 runloop 才改 @Published store，避免在 sheet 關閉的
        // view-update 交易裡同步改 observed state（父頁堆多個 sheet）造成真機閃退。
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }

    private func deleteRecord() {
        guard !isSaving else { return }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        isSaving = true
        e.photoFileNames.forEach { ElevatorMaintenance.deletePhoto($0) }
        estate.elevatorMaintenances.removeAll { $0.id == e.id }
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }
}

// MARK: - 水電瓦斯繳費編輯

struct UtilityPaymentEditor: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    let estateId: UUID
    let editing: UtilityPayment?

    @State private var type: UtilityType = .water
    @State private var date = Date()
    @State private var amountText = ""
    @State private var note = ""
    /// [v25.560] 這一期是哪一個表（同一種有兩個以上的表才問）；nil＝不指定，算在那一種的第一個表
    @State private var meterId: String?
    // 收據照片（多張）：改用 MultiPhotoGallery（可拍照連拍 / 相簿多選 / 燈箱檢視 / 刪除）
    @State private var photoFileNames: [String] = []
    @State private var showDeleteConfirm = false
    @State private var showError = false
    @State private var selectedBankMilestoneId: UUID?
    @State private var selectedBankCurrency: String = "NT$"
    @State private var selectedCreditCardMilestoneId: UUID?
    // 防止「儲存」連點：save() 把實際寫回 store 的動作延後到下個 runloop（見 save() 內註解），
    // 快速連點兩下會在第一次寫入完成前就再次進入 save()，各自建立一筆 Expense、並各自捕捉
    // 自己的 estate 快照非同步寫回，後寫入者會蓋掉前者剛 append 的 UtilityPayment，留下孤兒 Expense。
    @State private var isSaving = false

    private var bankMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .bank
        }
    }

    /// [v25.560] 這間房子這一種的每一個表（跟卡片上的列同一份：RealEstate.utilityMeterSlots）
    private var meterChoices: [UtilityMeterSlot] {
        guard let estate = store.realEstates.first(where: { $0.id == estateId }) else { return [] }
        let t = type
        return estate.utilityMeterSlots().filter { $0.type == t }
    }

    private var creditCardMilestones: [LifeMilestone] {
        lifeStore.milestones.filter {
            $0.category == .achievement && $0.financeSubCategory == .creditCard
        }
    }

    private var hasPaymentTargets: Bool {
        !bankMilestones.isEmpty || !creditCardMilestones.isEmpty
    }

    private var bankPickerLabel: String {
        if let id = selectedCreditCardMilestoneId,
           let card = creditCardMilestones.first(where: { $0.id == id }) {
            return card.cardName ?? card.title
        }
        if let id = selectedBankMilestoneId,
           let ms = bankMilestones.first(where: { $0.id == id }) {
            let name = ms.bankName ?? ms.title
            return "\(name) · \(selectedBankCurrency)"
        }
        return "未選擇"
    }

    private func bankCurrencies(for ms: LifeMilestone) -> [String] {
        let codes = (ms.bankDeposits ?? [])
            .filter { !$0.isWithdrawal }
            .map(\.currencyCode)
        var unique: [String] = []
        for c in codes where !unique.contains(c) { unique.append(c) }
        return unique.isEmpty ? ["NT$"] : unique
    }

    /// [v25.560] 「哪一個表」：不指定＝算在這一種的第一個表
    private var meterPicker: some View {
        Picker("哪一個表", selection: $meterId) {
            Text("不指定").tag(String?.none)
            ForEach(meterChoices) { slot in
                Text(slot.menuTitle).tag(Optional(slot.id))
            }
        }
    }

    private var meterFooter: String {
        let label: String
        switch type {
        case .water: label = "水號"
        case .electricity: label = "電號"
        case .gas: label = "瓦斯表"
        }
        return "這間有好幾個\(label)，選好是哪一個，卡片上每一個表就會顯示它自己的最近一期。"
    }

    /// 換了水電類型：原本選的表不是這一種的就清掉（讀進來的那一筆本來就對得上，不會被清）
    private func typeChanged() {
        guard let id = meterId else { return }
        if !meterChoices.contains(where: { $0.id == id }) { meterId = nil }
    }

    @ViewBuilder
    private func bankSubMenu(for ms: LifeMilestone) -> some View {
        let name = ms.bankName ?? ms.title
        let currencies = bankCurrencies(for: ms)
        if currencies.count > 1 {
            Menu(name) {
                ForEach(currencies, id: \.self) { code in
                    Button(code) {
                        selectedBankMilestoneId = ms.id
                        selectedBankCurrency = code
                        selectedCreditCardMilestoneId = nil
                    }
                }
            }
        } else {
            Button(name) {
                selectedBankMilestoneId = ms.id
                selectedBankCurrency = currencies.first ?? "NT$"
                selectedCreditCardMilestoneId = nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("類型", selection: $type) {
                        ForEach(UtilityType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    if meterChoices.count >= 2 {
                        meterPicker
                    }
                    DatePicker("繳費日期", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("NT$").foregroundStyle(.secondary)
                        TextField("金額", text: $amountText).keyboardType(.decimalPad)
                    }
                } header: {
                    realEstateEditorSectionHeader("基本資訊", icon: "list.bullet.rectangle.fill", color: .indigo)
                } footer: {
                    if meterChoices.count >= 2 {
                        Text(meterFooter)
                    }
                }

                if hasPaymentTargets {
                    Section {
                        HStack {
                            Text("扣款目標").foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("不指定") {
                                    selectedBankMilestoneId = nil
                                    selectedBankCurrency = "NT$"
                                    selectedCreditCardMilestoneId = nil
                                }
                                if !bankMilestones.isEmpty {
                                    Section("銀行") {
                                        ForEach(bankMilestones) { ms in
                                            bankSubMenu(for: ms)
                                        }
                                    }
                                }
                                if !creditCardMilestones.isEmpty {
                                    Section("信用卡") {
                                        ForEach(creditCardMilestones) { card in
                                            Button(card.cardName ?? card.title) {
                                                selectedCreditCardMilestoneId = card.id
                                                selectedBankMilestoneId = card.linkedBankMilestoneId
                                                selectedBankCurrency = "NT$"
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(bankPickerLabel)
                                        .foregroundStyle((selectedBankMilestoneId == nil && selectedCreditCardMilestoneId == nil) ? .secondary : .primary)
                                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("選擇扣款銀行或信用卡，繳費會自動連動該帳戶圖表。")
                    }
                }

                Section {
                    MultiPhotoGallery(
                        fileNames: $photoFileNames,
                        urlFor: { UtilityPayment.photosDirectory.appendingPathComponent($0) },
                        onSaveImage: { UtilityPayment.savePhoto($0, id: UUID()) },
                        onDeleteFile: { UtilityPayment.deletePhoto($0) },
                        title: "收據照片"
                    )
                } header: {
                    realEstateEditorSectionHeader("收據照片", icon: "photo.on.rectangle.angled", color: .teal)
                }

                Section {
                    TextField("選填備註", text: $note, axis: .vertical).lineLimit(3)
                } header: {
                    realEstateEditorSectionHeader("備註", icon: "note.text", color: .secondary)
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("刪除此記錄", systemImage: "trash")
                        }
                    }
                }

                if showError {
                    Section {
                        Text("請輸入有效金額").foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(editing == nil ? "新增繳費紀錄" : "編輯繳費紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // 本次 session 新拍/新選的照片已寫入磁碟但未儲存進紀錄，
                        // 取消時清掉避免孤兒檔案（既有照片不動；同型寫法見 RenovationPhotoEditor.cancel）
                        let original = Set(editing?.photoFileNames ?? [])
                        for name in photoFileNames where !original.contains(name) {
                            UtilityPayment.deletePhoto(name)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { save() }.bold().foregroundStyle(.green).disabled(isSaving)
                }
            }
            .onChange(of: type) { _, _ in typeChanged() }
            .onAppear {
                if let e = editing {
                    type = e.type
                    date = e.date
                    // [v25.530] 不用 %.0f：有小數的金額讀回來會被四捨五入，再存一次就改掉了
                    amountText = e.amount > 0 ? Self.editableAmountText(e.amount) : ""
                    note = e.note
                    meterId = e.meterId
                    photoFileNames = e.photoFileNames
                    // 載入既有的扣款目標（從連結的 Expense 讀回）
                    if let expId = e.linkedExpenseId,
                       let exp = expenseStore.expenses.first(where: { $0.id == expId }) {
                        selectedBankMilestoneId = exp.linkedBankMilestoneId
                        selectedBankCurrency = exp.linkedBankCurrency ?? "NT$"
                        selectedCreditCardMilestoneId = exp.linkedCreditCardMilestoneId
                    }
                }
            }
            .alert("確定刪除？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) { deleteRecord() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard let amount = Double(amountText), amount > 0 else {
            showError = true; return
        }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }) else { return }
        isSaving = true
        let recordId = editing?.id ?? UUID()
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let bankCurrency: String? = selectedBankMilestoneId != nil ? selectedBankCurrency : nil

        // [v25.530] 連結的支出還在：只改這個編輯器管的欄位（金額、日期、分類、扣款帳戶），
        // 你在記帳那邊改過的標題、地點、備註、照片都留著，id 也不變——以前每存一次就整筆重建蓋掉。
        // 找不到（被刪了，或這筆是新增的）才新建一筆並重新連結，不留指向不存在支出的連結。
        let previousExpense: Expense? = {
            guard let id = editing?.linkedExpenseId else { return nil }
            return expenseStore.expenses.first(where: { $0.id == id })
        }()
        let expense: Expense
        if var existing = previousExpense {
            existing.amount = amount
            existing.date = date
            existing.expenseType = .variable
            existing.variableCategory = .realEstate
            existing.fixedCategory = nil
            existing.recurrence = nil
            existing.realEstateExpenseCategory = .utility
            existing.linkedRealEstateId = estate.id
            existing.linkedBankMilestoneId = selectedBankMilestoneId
            existing.linkedBankCurrency = bankCurrency
            existing.linkedCreditCardMilestoneId = selectedCreditCardMilestoneId
            // 水電類型真的換了才動標題：標題裡有舊類型的字就只換那幾個字，其餘照你改過的留著
            if let oldType = editing?.type, oldType != type {
                if let r = existing.title.range(of: oldType.rawValue, options: .backwards) {
                    existing.title.replaceSubrange(r, with: type.rawValue)
                } else {
                    existing.title = "\(estate.name) - \(type.rawValue)"
                }
            }
            expenseStore.update(existing)
            expense = existing
        } else {
            let created = Expense(
                id: UUID(),
                title: "\(estate.name) - \(type.rawValue)",
                amount: amount,
                date: date,
                expenseType: .variable,
                variableCategory: .realEstate,
                linkedRealEstateId: estate.id,
                realEstateExpenseCategory: .utility,
                note: trimmedNote,
                linkedBankMilestoneId: selectedBankMilestoneId,
                linkedBankCurrency: bankCurrency,
                linkedCreditCardMilestoneId: selectedCreditCardMilestoneId
            )
            expenseStore.add(created)
            expense = created
        }
        // 舊連結指向的支出已經不在時，它留在銀行的扣款紀錄也一起清掉
        var clearIds: Set<UUID> = [expense.id]
        if let oldId = editing?.linkedExpenseId { clearIds.insert(oldId) }
        syncBankWithdrawal(for: expense, clearing: clearIds)

        var record = UtilityPayment(
            id: recordId, type: type, date: date, amount: amount,
            photoFileName: photoFileNames.first,
            photoFileNames: photoFileNames,
            note: trimmedNote,
            linkedExpenseId: expense.id
        )
        // [v25.560] 只存這一種真的有的表（換了類型、表被刪掉就不指定）
        let chosenMeter = meterId
        record.meterId = estate.utilityMeterSlots().contains { $0.type == type && $0.id == chosenMeter } ? chosenMeter : nil
        if let idx = estate.utilityPayments.firstIndex(where: { $0.id == recordId }) {
            estate.utilityPayments[idx] = record
        } else {
            estate.utilityPayments.append(record)
        }
        // 先關閉 sheet，下一個 runloop 才改 @Published store（避免真機 present/dismiss 交易期間改 observed state 閃退）
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }

    private func deleteRecord() {
        guard !isSaving else { return }
        guard var estate = store.realEstates.first(where: { $0.id == estateId }),
              let e = editing else { return }
        isSaving = true
        for name in e.photoFileNames { UtilityPayment.deletePhoto(name) }
        // [v25.530] 連結的支出（含照片）和所有帳戶裡它的扣款紀錄一起清；
        // 以前只清支出上記的那個帳戶，換過帳戶留下的舊紀錄會一直扣著
        if let linkedId = e.linkedExpenseId {
            RealEstateDeletion.removeExpenses([linkedId], expenseStore: expenseStore, lifeStore: lifeStore)
        }
        estate.utilityPayments.removeAll { $0.id == e.id }
        let financeStore = store
        dismiss()
        DispatchQueue.main.async { financeStore.update(estate) }
    }

    /// [v25.530] 同步銀行扣款紀錄：先把所有帳戶裡連到 ids 的舊紀錄清掉（換了扣款帳戶時，舊帳戶那筆
    /// 也要清，不管金額有沒有變），再寫一筆到目前的扣款帳戶。milestones 只寫一次。
    private func syncBankWithdrawal(for expense: Expense, clearing ids: Set<UUID>) {
        func isLinked(_ d: BankDeposit) -> Bool {
            guard let id = d.linkedExpenseId else { return false }
            return ids.contains(id)
        }
        var milestones = lifeStore.milestones
        var changed = false
        for i in milestones.indices {
            guard let deposits = milestones[i].bankDeposits, deposits.contains(where: isLinked) else { continue }
            milestones[i].bankDeposits = deposits.filter { !isLinked($0) }
            changed = true
        }
        // 信用卡扣款不寫入 BankDeposit；改在顯示時依月份彙總
        if expense.linkedCreditCardMilestoneId == nil,
           let bankId = expense.linkedBankMilestoneId,
           let idx = milestones.firstIndex(where: { $0.id == bankId }) {
            let value = realEstateBankWithdrawalValue(ntd: expense.amount, currency: expense.linkedBankCurrency, rates: expenseStore.currencyRates)
            var list = milestones[idx].bankDeposits ?? []
            list.append(BankDeposit(
                id: UUID(), date: expense.date, amount: value.amount,
                currencyCode: value.code,
                isWithdrawal: true, linkedExpenseId: expense.id
            ))
            milestones[idx].bankDeposits = list
            changed = true
        }
        if changed { lifeStore.milestones = milestones }
    }

    /// [v25.530] 金額帶回輸入框：四捨五入到 2 位小數再去掉多餘的 0（1234.5 → "1234.5"、1200 → "1200"）
    private static func editableAmountText(_ value: Double) -> String {
        let rounded: Double = (value * 100).rounded() / 100
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

/// [v25.530] 扣款帳戶是外幣子帳戶時，台幣金額用設定裡的匯率換成那個幣別再記
/// （銀行頁也是用同一個匯率把外幣換回台幣，兩邊對得上）。AddExpenseView 目前是直接把台幣數字
/// 標成外幣，沒有可照抄的換算，所以改用 currencyRates；設定裡找不到這個幣別的匯率時，
/// 就記成 NT$ 原額，至少不會把台幣數字標成外幣。水電瓦斯編輯器、卡片頁複製支出、編輯頁保險／附屬資產共用這一個。
func realEstateBankWithdrawalValue(ntd: Double, currency: String?, rates: [CurrencyRate]) -> (amount: Double, code: String) {
    guard let code = currency, !code.isEmpty else { return (ntd, "NT$") }
    if code == "NT$" || code == "TWD" { return (ntd, code) }
    if let rate = rates.first(where: { $0.code == code }), rate.rate > 0 {
        let converted: Double = (ntd / rate.rate * 100).rounded() / 100
        return (converted, code)
    }
    return (ntd, "NT$")
}

// MARK: - 房屋資料集錦：可愛風照片瀏覽器

struct CutePhotoDraft: Identifiable {
    enum Kind {
        case renovation
        case expense
        case utility(UtilityType)
        case elevator
        case vehicle(VehiclePhotoCategory)   // 車輛照片紀錄（VehicleDetailView 共用本瀏覽器）
        /// [v25.543] 股利發放通知書、扣繳憑單（股票帳本的照片膠囊開這個）
        case dividend
        /// [v25.559] 信用卡說明（權益說明、優惠 DM；理財卡片的信用卡「說明照片」開這個）
        case creditCard

        var label: String {
            switch self {
            case .renovation: return "裝潢紀錄"
            case .expense: return "支出照片"
            case .utility(let t): return "\(t.rawValue) 收據"
            case .elevator: return "電梯保養"
            case .vehicle(let c): return c.rawValue
            case .dividend: return "股利文件"
            case .creditCard: return "信用卡說明"
            }
        }
        var icon: String {
            switch self {
            case .renovation: return "paintbrush.fill"
            case .expense: return "tag.fill"
            case .utility(let t): return t.icon
            case .elevator: return "arrow.up.arrow.down.square.fill"
            case .vehicle(let c): return c.icon
            case .dividend: return "doc.text.image"
            case .creditCard: return "creditcard.fill"
            }
        }
        var accent: Color {
            switch self {
            case .renovation: return Color(red: 0.82, green: 0.55, blue: 0.92)   // 粉紫
            case .expense:    return Color(red: 0.98, green: 0.62, blue: 0.45)   // 蜜桃
            case .utility(let t):
                switch t {
                case .water:       return Color(red: 0.40, green: 0.70, blue: 0.95)   // 海藍
                case .electricity: return Color(red: 0.98, green: 0.78, blue: 0.30)   // 暖黃
                case .gas:         return Color(red: 0.96, green: 0.55, blue: 0.35)   // 蜜橘
                }
            case .elevator: return Color(red: 0.45, green: 0.78, blue: 0.70)   // 薄荷綠
            case .vehicle(let c): return c.color
            case .dividend: return Color(red: 0.95, green: 0.70, blue: 0.25)   // 暖金（和股利柱同一個色系）
            case .creditCard: return Color(red: 0.98, green: 0.58, blue: 0.30)   // 橙（跟理財卡片的信用卡同色系）
            }
        }
    }

    let id = UUID()
    let urls: [URL]
    let title: String
    let note: String
    let date: Date
    let kind: Kind
}

/// 可愛風照片瀏覽器：粉色漸層背景 + 圓角描邊照片 + 自訂頁碼點 + 友善資訊卡。
/// 支援雙指縮放（內含 ZoomableImageView）+ 多張左右滑動切換。
struct CutePhotoViewer: View {
    let draft: CutePhotoDraft
    @Environment(\.dismiss) private var dismiss
    /// [v25.534] 背景、資訊卡跟著深淺色走（以前寫死淡粉，深色模式整片亮白）。車卡也共用這個檢視器，一起變
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentIndex: Int = 0

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            backgroundGradient
            decorativeOrbs

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 4)
                photoArea
                Spacer(minLength: 4)
                // 目前這張的照片資訊：檔名 / 解析度 / 檔案大小（與 PhotoLightbox 共用 PhotoInfoBar）。
                // 本視圖（CutePhotoViewer）才是裝潢／支出／水電／電梯保養四類照片實際會開啟的檢視器；
                // RenovationStackViewer／ExpensePhotoStackViewer 是同語意但從未被任何呼叫端建立的死碼，
                // v25.65 當時把 PhotoInfoBar 接到了那兩個死碼元件，本體 CutePhotoViewer 反而漏接。
                if draft.urls.indices.contains(currentIndex) {
                    PhotoInfoBar(url: draft.urls[currentIndex])
                        .padding(.bottom, 4)
                }
                if draft.urls.count > 1 {
                    pageDots
                        .padding(.bottom, 4)
                }
                infoCard
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: 背景

    private var backgroundGradient: some View {
        LinearGradient(
            colors: isDark ? Self.darkBackground : Self.lightBackground,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// 淡桃、淡粉、淡紫
    private static let lightBackground: [Color] = [
        Color(red: 1.00, green: 0.94, blue: 0.93),
        Color(red: 1.00, green: 0.90, blue: 0.94),
        Color(red: 0.94, green: 0.90, blue: 1.00)
    ]
    /// 深色：同一組色相的深底（照片才是主角，背景不能比照片亮）
    private static let darkBackground: [Color] = [
        Color(red: 0.13, green: 0.10, blue: 0.12),
        Color(red: 0.12, green: 0.09, blue: 0.13),
        Color(red: 0.09, green: 0.08, blue: 0.15)
    ]

    /// 資訊卡標題字：淺色深紫、深色淡紫
    private var titleInk: Color {
        isDark ? Color(red: 0.90, green: 0.86, blue: 0.97) : Color(red: 0.25, green: 0.18, blue: 0.35)
    }
    private var noteInk: Color {
        isDark ? Color(red: 0.80, green: 0.76, blue: 0.88) : Color(red: 0.35, green: 0.3, blue: 0.45)
    }
    /// 資訊卡底：淺色白、深色深灰
    private var cardFill: Color {
        isDark ? Color(white: 0.16).opacity(0.92) : Color.white.opacity(0.85)
    }
    private var cardSheen: Color {
        isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.6)
    }
    /// 照片的白框：深色模式調暗，不然一圈亮白很刺眼
    private var photoFrame: Color {
        isDark ? Color.white.opacity(0.22) : Color.white
    }
    private var cardStroke: Color {
        isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.7)
    }

    /// 角落漂浮的兩顆柔光圓球，讓畫面更活潑
    private var decorativeOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(draft.kind.accent.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .blur(radius: 50)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.32)
                Circle()
                    .fill(Color.pink.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.32, y: geo.size.height * 0.18)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 上方 chrome

    private var topBar: some View {
        HStack {
            // 關閉按鈕：改放左側，對齊全 App「關閉／取消」統一放左側的慣例（見 PhotoLightbox）
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(draft.kind.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(draft.kind.accent.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            // 來源膠囊
            HStack(spacing: 6) {
                Image(systemName: draft.kind.icon)
                    .font(.caption.weight(.bold))
                Text(draft.kind.label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [draft.kind.accent, draft.kind.accent.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: draft.kind.accent.opacity(0.35), radius: 6, y: 3)

            // [v25.471] 存到相簿／分享（與其餘圖片預覽共用同一組按鈕）。
            // 這個檢視器是左關閉、右來源膠囊，所以兩顆接在膠囊後面——
            // 位置仍然是右上角，與其他預覽對得上。
            if draft.urls.indices.contains(currentIndex) {
                PhotoActionButtons(url: draft.urls[currentIndex])
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    // MARK: 主照片區

    private var photoArea: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(draft.urls.enumerated()), id: \.offset) { idx, url in
                photoCard(url: url)
                    .tag(idx)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func photoCard(url: URL) -> some View {
        GeometryReader { geo in
            AsyncLocalImage(url: url) { img, didLoad in
                Group {
                    if let img {
                        ZStack {
                            // 模糊填底：填滿卡片、補滿留白；裁切在白框內不外溢
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .blur(radius: 18, opaque: true)
                                .overlay(Color.black.opacity(0.06))

                            // 原圖：完整顯示（橫圖也不會超出，可雙指縮放）
                            ZoomableImageView(image: img)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(photoFrame, lineWidth: 4)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 14, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                VStack(spacing: 10) {
                                    if didLoad {
                                        Image(systemName: "photo.fill.on.rectangle.fill")
                                            .font(.system(size: 40))
                                            .foregroundStyle(draft.kind.accent.opacity(0.6))
                                        Text("找不到照片")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        // [v12] 補齊主題色，避免載入中→找不到照片切換時顏色從灰轉彩
                                        ProgressView()
                                            .tint(draft.kind.accent)
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(photoFrame, lineWidth: 4)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: 自訂頁碼點

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<draft.urls.count, id: \.self) { idx in
                Capsule()
                    .fill(idx == currentIndex
                          ? draft.kind.accent
                          : Color.gray.opacity(0.3))
                    .frame(
                        width: idx == currentIndex ? 18 : 6,
                        height: 6
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.7),
                               value: currentIndex)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
    }

    // MARK: 底部資訊卡

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("📸")
                    .font(.title3)
                MarqueeText(draft.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(titleInk)
                Spacer()
                if draft.urls.count > 1 {
                    Text("\(currentIndex + 1) / \(draft.urls.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(draft.kind.accent)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(
                            Capsule().fill(draft.kind.accent.opacity(0.15))
                        )
                }
            }
            if !draft.note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("💬")
                    Text(draft.note)
                        .font(.subheadline)
                        .foregroundStyle(noteInk)
                        .lineLimit(4)
                }
            }
            HStack(spacing: 6) {
                Text("📅")
                Text(fmtDate(draft.date))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(cardFill)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(colors: [
                            cardSheen,
                            draft.kind.accent.opacity(0.08)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: -2)
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
    }

    private static let _dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy 年 M 月 d 日"
        f.locale = Locale(identifier: "zh_TW")
        // [v25.530] 固定西元曆（手機設成民國曆時不會印出「0115 年」）
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
    private func fmtDate(_ d: Date) -> String { Self._dateFmt.string(from: d) }
}

// MARK: - 文件預覽（QuickLook 包裝）

/// 用 QLPreviewController 預覽 PDF / PPT / Excel / Word 等，支援 Apple 內建的縮放與分享。
/// 以 sheet 包裹呈現，使用者下拉即可關閉。
/// [v25.534] 外面包一層 UINavigationController：QLPreviewController 要放在導覽列裡，
/// 「完成」和「分享」按鈕才會出現（以前直接當 sheet 內容，畫面上沒有任何按鈕）。
struct DocumentQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - 樓層物件編輯

/// 樓層物件編輯目標：
/// - itemId 為 nil → 新增（parentItemId 為 nil = 加到樓層根，否則加到指定父節點底下）
/// - itemId 非 nil → 重新命名既有節點
struct FloorItemEditTarget: Identifiable {
    let id = UUID()
    let floorId: UUID
    let parentItemId: UUID?
    let itemId: UUID?
    let currentName: String
}

/// 簡單的樓層物件命名 sheet：一個 TextField + 取消 / 儲存
struct FloorItemEditor: View {
    let initialName: String
    let isEditing: Bool
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var focused: Bool
    /// onSave 最終寫回 store 是延後一個 runloop 的非同步操作（見 commitFloorEstate 註解），
    /// sheet 收合動畫播完前快速連點「儲存」會讓兩次呼叫都讀到同一份舊 estate 快照各自
    /// append，較晚落地的一次會覆蓋掉較早一次的結果，其中一筆新增物件會憑空消失；
    /// 比照既有 isSaving 寫法鎖住按鈕，確保只送出一次。
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：衣櫃 / 第一格", text: $name)
                        .focused($focused)
                } header: {
                    realEstateEditorSectionHeader("物件名稱", icon: "shippingbox.fill", color: .brown)
                }
            }
            .navigationTitle(isEditing ? "重新命名物件" : "新增物件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        guard !isSaving else { return }
                        isSaving = true
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                name = initialName
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    focused = true
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - 縮圖快取（降採樣 + 非同步 + NSCache）

/// 以 ImageIO 降採樣產生小縮圖，避免主執行緒解碼全解析度大圖造成卡頓；結果快取於記憶體。
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() { cache.countLimit = 500 }

    func thumbnail(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = Self.downsample(url: url, maxPixel: maxPixel)
                if let img { self.cache.setObject(img, forKey: key) }  // NSCache 為 thread-safe
                cont.resume(returning: img)
            }
        }
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOpts) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel))
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 縮圖檢視：先顯示佔位，背景降採樣載入後淡入；切換 url 會重載。
struct ThumbnailImageView: View {
    let url: URL?
    var maxPixel: CGFloat = 420
    var placeholderIcon: String? = nil
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                if let placeholderIcon {
                    Image(systemName: placeholderIcon)
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task(id: url?.path) {
            // 先清空再讀，讓「url 改變」單純由 .task(id:) 本身的重觸發機制控管，
            // 避免更換照片後畫面短暫停留在舊縮圖，對齊 AsyncLocalImage 同型修復。
            image = nil
            guard let url else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: maxPixel)
        }
    }
}
