import SwiftUI

// MARK: - 主畫面

struct EInvoiceSetupView: View {
    @EnvironmentObject var sync: EInvoiceSyncManager
    @EnvironmentObject var expenseStore: ExpenseStore
    @StateObject private var categorizer = InvoiceCategorizer.shared

    @State private var inputCardNo: String = ""
    @State private var inputCardEncrypt: String = ""
    @State private var showLinkAlert: Bool = false
    @State private var linkAlertMessage: String = ""
    @State private var showSyncResult: Bool = false
    @State private var showRulesEditor: Bool = false
    @State private var showHistory: Bool = false

    var body: some View {
        Form {
            if !sync.isLinked {
                linkSection
                aboutSection
            } else {
                statusSection
                syncSettingsSection
                actionsSection
                historySummarySection
                rulesShortcutSection
                aboutSection
                unlinkSection
            }
        }
        .navigationTitle("電子發票自動匯入")
        .navigationBarTitleDisplayMode(.inline)
        .alert("連結結果", isPresented: $showLinkAlert) {
            Button("確定") {}
        } message: {
            Text(linkAlertMessage)
        }
        .alert("同步完成", isPresented: $showSyncResult) {
            Button("確定") {}
        } message: {
            if let r = sync.lastSync {
                if r.errors.isEmpty {
                    Text(r.summary)
                } else {
                    Text(r.summary + "\n\n錯誤：\n" + r.errors.prefix(3).joined(separator: "\n"))
                }
            } else {
                Text("尚無同步結果。")
            }
        }
        .sheet(isPresented: $showRulesEditor) {
            CategoryRulesEditorView()
                .environmentObject(categorizer)
        }
        .sheet(isPresented: $showHistory) {
            EInvoiceHistoryView()
                .environmentObject(sync)
                .environmentObject(expenseStore)
        }
        .onAppear {
            if let c = sync.carrier {
                inputCardNo = c.cardNo
                inputCardEncrypt = c.cardEncrypt
            }
        }
    }

    // MARK: - Section：尚未連結

    private var linkSection: some View {
        Section {
            TextField("手機條碼（含斜線，例：/ABC1234）", text: $inputCardNo)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
            SecureField("驗證碼", text: $inputCardEncrypt)

            Button {
                attemptLink()
            } label: {
                Label("連結載具", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .disabled(inputCardNo.isEmpty || inputCardEncrypt.isEmpty)
        } header: {
            Text("連結手機條碼載具")
        } footer: {
            Text("輸入財政部電子發票手機條碼與驗證碼即可自動匯入消費紀錄。資料只存在本機（驗證碼存於 iOS Keychain），LifeGood 不會上傳任何資料。")
        }
    }

    private func attemptLink() {
        // 簡易格式檢查
        let pattern = #"^/[A-Z0-9.\-+]{7}$"#
        let cardOK = inputCardNo.range(of: pattern, options: .regularExpression) != nil
        guard cardOK else {
            linkAlertMessage = "手機條碼格式錯誤，需為「/」開頭加 7 碼大寫英數，例如：/ABC1234"
            showLinkAlert = true
            return
        }
        sync.linkCarrier(cardNo: inputCardNo, cardEncrypt: inputCardEncrypt)
        linkAlertMessage = "已連結。可使用「立即同步」測試是否成功。"
        showLinkAlert = true
    }

    // MARK: - Section：已連結 → 狀態

    private var statusSection: some View {
        Section("目前狀態") {
            HStack {
                Label("載具", systemImage: "creditcard.fill")
                Spacer()
                Text(sync.carrier?.cardNo ?? "—").foregroundStyle(.secondary).monospaced()
            }
            HStack {
                Label("最近同步", systemImage: "clock")
                Spacer()
                Text(sync.lastSyncDate.map(formatDateTime) ?? "尚未同步")
                    .foregroundStyle(.secondary).font(.caption)
            }
            if EInvoiceClient.appID.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("尚未設定 appID，所有同步會失敗。請至 https://www.einvoice.nat.gov.tw/ESCAPI/ 申請後填入 EInvoiceClient.appID。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var syncSettingsSection: some View {
        Section {
            Toggle("自動同步", isOn: $sync.autoSyncEnabled)
            if sync.autoSyncEnabled {
                Picker("同步間隔", selection: $sync.autoSyncIntervalHours) {
                    Text("每 6 小時").tag(6)
                    Text("每 12 小時").tag(12)
                    Text("每 24 小時").tag(24)
                    Text("每 3 天").tag(72)
                    Text("每 7 天").tag(168)
                }
            }
            Toggle("拆分品項", isOn: $sync.splitItems)
        } header: {
            Text("同步設定")
        } footer: {
            Text("關閉「拆分品項」時，整張發票合併成一筆變動支出。開啟後會依品項分別建立支出，方便細部分析（例如同一張發票拆出咖啡與飯糰）。")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await sync.syncNow(expenseStore: expenseStore)
                    showSyncResult = true
                }
            } label: {
                HStack {
                    Label("立即同步", systemImage: "arrow.clockwise")
                    Spacer()
                    if sync.isSyncing { ProgressView() }
                }
            }
            .disabled(sync.isSyncing)
        }
    }

    private var historySummarySection: some View {
        Section {
            Button {
                showHistory = true
            } label: {
                HStack {
                    Label("匯入歷史", systemImage: "list.bullet.clipboard")
                    Spacer()
                    Text("\(sync.importHistory.count) 筆").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var rulesShortcutSection: some View {
        Section {
            Button {
                showRulesEditor = true
            } label: {
                HStack {
                    Label("自動分類規則", systemImage: "tag.fill")
                    Spacer()
                    Text("\(categorizer.rules.count) 條").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
                }
            }
            .foregroundStyle(.primary)
        } footer: {
            Text("依商家或品項關鍵字將發票對應到 LifeGood 的變動支出分類。可新增或修改自訂規則。")
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            Link(destination: URL(string: "https://www.einvoice.nat.gov.tw/")!) {
                Label("財政部電子發票平台", systemImage: "globe")
            }
            Link(destination: URL(string: "https://www.einvoice.nat.gov.tw/ESCAPI/")!) {
                Label("申請 appID", systemImage: "key.fill")
            }
        }
    }

    private var unlinkSection: some View {
        Section {
            Button(role: .destructive) {
                sync.unlinkCarrier()
                inputCardNo = ""
                inputCardEncrypt = ""
            } label: {
                Label("中斷連結", systemImage: "link.badge.plus")
            }
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 分類規則編輯器

struct CategoryRulesEditorView: View {
    @EnvironmentObject var categorizer: InvoiceCategorizer
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd: Bool = false
    @State private var newKeyword: String = ""
    @State private var newCategory: VariableCategory = .food
    @State private var newMatchSeller: Bool = true
    @State private var newMatchItem: Bool = true
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newKeyword = ""
                        newCategory = .food
                        newMatchSeller = true
                        newMatchItem = true
                        showAdd = true
                    } label: {
                        Label("新增規則", systemImage: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("重設為預設規則", systemImage: "arrow.counterclockwise")
                    }
                }

                ForEach(VariableCategory.allCases) { cat in
                    let rules = categorizer.rules.filter { $0.category == cat }
                    if !rules.isEmpty {
                        Section {
                            ForEach(rules) { rule in
                                ruleRow(rule)
                            }
                            .onDelete { offsets in
                                offsets.forEach { categorizer.deleteRule(rules[$0]) }
                            }
                        } header: {
                            HStack {
                                Image(systemName: cat.icon)
                                Text(cat.rawValue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("自動分類規則")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重設規則？", isPresented: $showResetConfirm) {
                Button("重設", role: .destructive) { categorizer.resetToDefaults() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("會清除所有自訂規則並回到內建預設規則。")
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section("關鍵字") {
                            TextField("商家或品項關鍵字", text: $newKeyword)
                        }
                        Section("分類") {
                            Picker("變動支出分類", selection: $newCategory) {
                                ForEach(VariableCategory.allCases) { c in
                                    Label(c.rawValue, systemImage: c.icon).tag(c)
                                }
                            }
                        }
                        Section("比對範圍") {
                            Toggle("比對商家名稱", isOn: $newMatchSeller)
                            Toggle("比對品項描述", isOn: $newMatchItem)
                        }
                    }
                    .navigationTitle("新增規則")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { Button("取消") { showAdd = false } }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("新增") {
                                let rule = CategoryRule(
                                    keyword: newKeyword.trimmingCharacters(in: .whitespaces),
                                    category: newCategory,
                                    matchSeller: newMatchSeller,
                                    matchItem: newMatchItem,
                                    isUserDefined: true)
                                categorizer.addRule(rule)
                                showAdd = false
                            }
                            .bold()
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: CategoryRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.keyword).font(.subheadline)
                HStack(spacing: 6) {
                    if rule.matchSeller {
                        Text("商家").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if rule.matchItem {
                        Text("品項").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12)).foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if rule.isUserDefined {
                        Text("自訂").font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.green.opacity(0.12)).foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: - 匯入歷史

struct EInvoiceHistoryView: View {
    @EnvironmentObject var sync: EInvoiceSyncManager
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if sync.importHistory.isEmpty {
                    Section {
                        Text("尚無匯入紀錄").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sync.importHistory) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.sellerName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("NT$\(Int(record.amount))").font(.subheadline.bold())
                            }
                            HStack(spacing: 8) {
                                Text(formatDate(record.invDate)).font(.caption2).foregroundStyle(.tertiary)
                                Text(record.invNum).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                Spacer()
                                Label(record.assignedCategory.rawValue, systemImage: record.assignedCategory.icon)
                                    .font(.caption2).foregroundStyle(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                sync.revert(record, expenseStore: expenseStore)
                            } label: {
                                Label("撤銷", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("匯入歷史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
                if !sync.importHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                    }
                }
            }
            .alert("清除全部歷史？", isPresented: $showClearConfirm) {
                Button("清除", role: .destructive) { sync.clearHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("僅清除匯入紀錄，已建立的變動支出不會被刪除。")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}
