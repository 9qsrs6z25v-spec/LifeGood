import SwiftUI

// MARK: - 美化紀錄（EInvoiceSetupView）[2026-06]
// 美化方向：
//   1. 未連結英雄卡 (heroCard)：綠色漸層 + 48pt 圖示圓 + 散景裝飾圓，
//      說明功能並引導輸入，對齊 IncomeView / SettingsView heroCard 設計規格；
//      heroAppeared spring 進場動畫（透明度 + Y 位移）。
//   2. 已連結狀態卡 (statusHeroCard)：綠色漸層英雄卡，顯示載具號碼 Capsule 徽章 +
//      最近同步 Capsule；appID 警告改為橘色警示膠囊，對齊 AddExpenseView errorBanner 規格。
//   3. Section header：統一改用「4pt Capsule 色條 + 圖示 + .subheadline.semibold 標題」，
//      對齊 OverviewView / IncomeView 全 App section header 規格。
//   4. actionsSection「立即同步」按鈕：升級為綠色 Capsule 全寬主按鈕，
//      對齊 IncomeView emptyState CTA 按鈕設計。
//   5. historySummarySection / rulesShortcutSection：計數改為 Capsule 膠囊徽章，
//      對齊 OverviewView / LifeOverviewView count badge 規格。
//   6. CategoryRulesEditorView.ruleRow：
//      badge 從 RoundedRectangle(cornerRadius:3) 升級為 Capsule，
//      左側加 32pt 漸層圖示圓，對齊 VariableExpenseView expenseRow 規格。
//   7. EInvoiceHistoryView：
//      空狀態升級為雙層脈衝光環（teal）+ 漸層圓，對齊 IncomeView.emptyState 規格；
//      historyRow 左側加 36pt 漸層圖示圓；分類改為 Capsule 膠囊；
//      historyAppeared 進場動畫（交錯延遲）。

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

    // 進場動畫旗標
    @State private var heroAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !sync.isLinked {
                    heroCard
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.05)) {
                                heroAppeared = true
                            }
                        }
                    linkFormCard
                    aboutFormCard
                } else {
                    statusHeroCard
                        .opacity(heroAppeared ? 1 : 0)
                        .offset(y: heroAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.05)) {
                                heroAppeared = true
                            }
                        }
                    syncSettingsCard
                    actionsCard
                    historyAndRulesCard
                    aboutFormCard
                    unlinkCard
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
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

    // MARK: - 未連結英雄卡

    private var heroCard: some View {
        ZStack {
            // 散景裝飾圓
            Circle().fill(Color.white.opacity(0.12)).frame(width: 120, height: 120)
                .offset(x: 70, y: -30).blur(radius: 18)
            Circle().fill(Color.white.opacity(0.09)).frame(width: 80, height: 80)
                .offset(x: -60, y: 20).blur(radius: 14)

            VStack(spacing: 12) {
                // 圖示圓
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("電子發票自動匯入")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("連結手機條碼載具，消費發票自動轉為變動支出，無需手動輸入。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.18, green: 0.70, blue: 0.42),
                                    Color(red: 0.10, green: 0.55, blue: 0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.green.opacity(0.25), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 已連結狀態英雄卡

    private var statusHeroCard: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.10)).frame(width: 100, height: 100)
                .offset(x: 60, y: -20).blur(radius: 16)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("已連結載具")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                // 載具號碼 Capsule
                if let cardNo = sync.carrier?.cardNo {
                    Text(cardNo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.white.opacity(0.20))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 0.75))
                }

                // 最近同步
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.80))
                    Text(sync.lastSyncDate.map(formatDateTime) ?? "尚未同步")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.80))
                }

                // appID 警告
                if EInvoiceClient.appID.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                        Text("尚未設定 appID，同步功能無法使用")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 0.75))
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.18, green: 0.70, blue: 0.42),
                                    Color(red: 0.10, green: 0.55, blue: 0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.green.opacity(0.25), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 連結輸入表單卡

    private var linkFormCard: some View {
        VStack(spacing: 0) {
            einvoiceSectionHeader("連結手機條碼載具", icon: "creditcard.fill", color: .green)

            VStack(spacing: 12) {
                TextField("手機條碼（含斜線，例：/ABC1234）", text: $inputCardNo)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                SecureField("驗證碼", text: $inputCardEncrypt)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    attemptLink()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("連結載具")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        inputCardNo.isEmpty || inputCardEncrypt.isEmpty
                            ? Color.green.opacity(0.35)
                            : Color.green
                    )
                    .clipShape(Capsule())
                }
                .disabled(inputCardNo.isEmpty || inputCardEncrypt.isEmpty)

                Text("輸入財政部電子發票手機條碼與驗證碼即可自動匯入消費紀錄。資料只存在本機（驗證碼存於 iOS Keychain），LifeGood 不會上傳任何資料。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func attemptLink() {
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

    // MARK: - 同步設定卡

    private var syncSettingsCard: some View {
        VStack(spacing: 0) {
            einvoiceSectionHeader("同步設定", icon: "gear.badge", color: .blue)

            VStack(spacing: 0) {
                Toggle("自動同步", isOn: $sync.autoSyncEnabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)

                if sync.autoSyncEnabled {
                    Divider().padding(.leading, 16)
                    Picker("同步間隔", selection: $sync.autoSyncIntervalHours) {
                        Text("每 6 小時").tag(6)
                        Text("每 12 小時").tag(12)
                        Text("每 24 小時").tag(24)
                        Text("每 3 天").tag(72)
                        Text("每 7 天").tag(168)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }

                Divider().padding(.leading, 16)
                Toggle("拆分品項", isOn: $sync.splitItems)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }

            Text("關閉「拆分品項」時，整張發票合併成一筆變動支出。開啟後會依品項分別建立支出，方便細部分析。")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 動作卡（立即同步）

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    await sync.syncNow(expenseStore: expenseStore)
                    showSyncResult = true
                }
            } label: {
                HStack(spacing: 8) {
                    if sync.isSyncing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("立即同步")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(sync.isSyncing ? Color.green.opacity(0.50) : Color.green)
                .clipShape(Capsule())
            }
            .disabled(sync.isSyncing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 歷史 + 規則捷徑卡

    private var historyAndRulesCard: some View {
        VStack(spacing: 0) {
            einvoiceSectionHeader("紀錄與規則", icon: "list.bullet.clipboard.fill", color: .indigo)

            VStack(spacing: 0) {
                Button {
                    showHistory = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.teal, .blue],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: "list.bullet.clipboard")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Text("匯入歷史")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(sync.importHistory.count) 筆")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.teal.opacity(0.25), lineWidth: 0.75))

                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 62)

                Button {
                    showRulesEditor = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.purple, .indigo],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: "tag.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Text("自動分類規則")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(categorizer.rules.count) 條")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.purple.opacity(0.25), lineWidth: 0.75))

                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }

            Text("依商家或品項關鍵字將發票對應到 LifeGood 的變動支出分類。")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 關於卡

    private var aboutFormCard: some View {
        VStack(spacing: 0) {
            einvoiceSectionHeader("關於", icon: "info.circle.fill", color: .secondary)

            VStack(spacing: 0) {
                Link(destination: URL(string: "https://www.einvoice.nat.gov.tw/")!) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.8), .teal.opacity(0.8)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: "globe")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("財政部電子發票平台")
                            .font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }

                Divider().padding(.leading, 62)

                Link(destination: URL(string: "https://www.einvoice.nat.gov.tw/ESCAPI/")!) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.orange, .yellow],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: "key.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("申請 appID")
                            .font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - 取消連結卡

    private var unlinkCard: some View {
        Button(role: .destructive) {
            sync.unlinkCarrier()
            inputCardNo = ""
            inputCardEncrypt = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus")
                Text("中斷連結")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.red.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.20), lineWidth: 0.75))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Section Header 共用元件

    private func einvoiceSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)

            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
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
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.purple.opacity(0.75), .indigo.opacity(0.75)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                Text(cat.rawValue)
                                    .font(.subheadline.weight(.semibold))
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

    // 美化：badge 從 RoundedRectangle(cornerRadius:3) 升級為 Capsule + 左側 32pt 漸層圖示圓
    private func ruleRow(_ rule: CategoryRule) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.purple.opacity(0.75), .indigo.opacity(0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "tag.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.keyword).font(.subheadline)
                HStack(spacing: 5) {
                    if rule.matchSeller {
                        Text("商家").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12)).foregroundStyle(.blue)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 0.5))
                    }
                    if rule.matchItem {
                        Text("品項").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12)).foregroundStyle(.purple)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.purple.opacity(0.25), lineWidth: 0.5))
                    }
                    if rule.isUserDefined {
                        Text("自訂").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12)).foregroundStyle(.green)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.5))
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

    // 進場動畫 + 空狀態脈衝
    @State private var historyAppeared = false
    @State private var emptyPulse = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if sync.importHistory.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(sync.importHistory.enumerated()), id: \.element.id) { idx, record in
                            historyRow(record)
                                .opacity(historyAppeared ? 1 : 0)
                                .offset(y: historyAppeared ? 0 : 12)
                                .animation(
                                    .spring(response: 0.50, dampingFraction: 0.78).delay(0.04 * Double(min(idx, 12))),
                                    value: historyAppeared
                                )
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        sync.revert(record, expenseStore: expenseStore)
                                    } label: {
                                        Label("撤銷", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.08)) {
                            historyAppeared = true
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

    // 美化：36pt 漸層圖示圓 + 分類 Capsule 膠囊
    private func historyRow(_ record: ImportedInvoice) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.teal, .blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .shadow(color: .teal.opacity(0.30), radius: 4, x: 0, y: 2)
                Image(systemName: record.assignedCategory.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.sellerName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("NT$\(Int(record.amount))")
                        .font(.subheadline.bold())
                }
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: record.invDate))
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(record.invNum)
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    Spacer()
                    Text(record.assignedCategory.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.teal.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.teal.opacity(0.25), lineWidth: 0.5))
                }
            }
        }
    }

    // 美化：雙層脈衝光環空狀態，對齊 IncomeView.emptyState 規格
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.teal.opacity(emptyPulse ? 0.0 : 0.25), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                    .scaleEffect(emptyPulse ? 1.55 : 1.0)
                Circle()
                    .stroke(Color.teal.opacity(emptyPulse ? 0.0 : 0.15), lineWidth: 1)
                    .frame(width: 90, height: 90)
                    .scaleEffect(emptyPulse ? 1.90 : 1.0)
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.teal, .blue],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .shadow(color: .teal.opacity(0.35), radius: 10, x: 0, y: 4)
                    Image(systemName: "doc.text")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                    emptyPulse = true
                }
            }

            VStack(spacing: 6) {
                Text("尚無匯入紀錄").font(.headline)
                Text("同步後，電子發票將顯示於此")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}
