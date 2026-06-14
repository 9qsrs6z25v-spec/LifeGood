import SwiftUI
import UniformTypeIdentifiers

// MARK: - 美化紀錄（SettingsView）
// [2026-06] v1 美化方向：
//   1. 頂部訂閱狀態英雄卡：漸層背景 + 散景裝飾圓，對齊其他主要頁面 hero card 設計語言
//      Premium → 綠色漸層；免費 → 藍紫漸層（視覺提示升級動機）
//      顯示方案名稱、版本號、三模式記錄筆數 KPI 橫列
//   2. disclosureBlock 標題字重 .medium → .semibold，強化視覺層級對比
//   3. 英雄卡進場動畫（opacity + translateY spring），對齊 OverviewView summaryCard 規格
// [2026-06] v2 美化方向：
//   4. dataStatsSection 三模式統計徽章加入個別錯開進場動畫（stagger spring，0.07s 間隔）
//      opacity(0→1) + offset(y: 18→0)，對齊 LazyVStack stagger 規格
//   5. 展開 dataStatsSection 時重新觸發動畫（重設 dataStatBadgesAppeared），
//      每次 DisclosureGroup 展開都有流暢進場效果
// [2026-06] v3 美化方向：
//   6. settingsActionRow 輔助函式：統一 dataManagementSection 各匯出/匯入按鈕為
//      「36pt LinearGradient 漸層圓 + subheadline.medium 主標 + caption 副標 + chevron.right」，
//      對齊 CareerView.careerRow / SubordinateDetailView.recordRow 列式卡規格。
//   7. subscriptionSection：「已訂閱」從裸 Text 升級為綠色 Capsule 膠囊徽章；
//      「還原購買」/ 「管理訂閱」按鈕補 36pt 漸層圖示圓，對齊 dataManagementSection 行列規格。
//   8. iCloudSyncSection：「iCloud 帳號」已登入/未登入 → 彩色 Capsule 狀態徽章；
//      「同步狀態」/ 「最近同步」/ 「最近事件」/ 「同步錯誤」右側值 → Capsule 徽章；
//      「立即同步」/ 「重新選擇同步方式」補 36pt 漸層圖示圓，對齊 dataManagementSection 規格。
//   9. restoreSection：復原按鈕補 36pt 橘色漸層圖示圓，對齊 dataManagementSection 規格。

// MARK: - Share Sheet (UIKit bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 分享項目

enum ShareItem: Identifiable {
    case json(URL)
    case csv(URL)
    case backup(URL)

    var id: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        case .backup: return "backup"
        }
    }

    var url: URL {
        switch self {
        case .json(let url), .csv(let url), .backup(let url): return url
        }
    }
}

// MARK: - 設定頁面

struct SettingsView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var cloudSync: CloudSyncManager
    @EnvironmentObject var subscription: SubscriptionManager
    @EnvironmentObject var einvoiceSync: EInvoiceSyncManager
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue
    @State private var showPaywall: Bool = false

    private var currentMode: AppMode {
        get { AppMode(rawValue: appMode) ?? .expense }
    }

    // 匯出狀態
    @State private var activeShareItem: ShareItem?
    @State private var exportErrorMessage = ""
    @State private var showExportError = false

    // 匯入狀態
    @State private var showImporter = false
    @State private var showImportModeAlert = false
    @State private var pendingImportData: Data?
    @State private var pendingBackupURL: URL?      // 完整備份檔（含照片）匯入用
    @State private var backupBusy = false
    @State private var importResultMessage = ""
    @State private var showImportResult = false

    // 清除狀態
    @State private var showClearConfirm = false

    // 復原狀態
    @State private var showRestoreConfirm = false
    @State private var restoreCandidate: (url: URL, date: Date)?
    @State private var showRestoreResult = false
    @State private var restoreResultMessage = ""

    @State private var subscriptionExpanded = true   // 訂閱常會看，預設開
    @State private var einvoiceExpanded = false
    @State private var currencyExpanded = false
    @State private var iCloudExpanded = false
    @State private var aiExpanded = false
    @State private var dataManagementExpanded = false
    @State private var dataStatsExpanded = false
    @State private var restoreExpanded = false
    @State private var aboutExpanded = false
    @StateObject private var aiSettings = AISettingsStore.shared
    @State private var heroCardAppeared = false
    @State private var dataStatBadgesAppeared: [Bool] = [false, false, false]

    // 隱藏管理控制台（關於頁連點 20 下）
    @StateObject private var remoteAdmin = RemoteAdminManager.shared
    @State private var aboutTapCount = 0
    @State private var showAdminConsole = false

    var body: some View {
        NavigationStack {
            List {
                // 英雄卡：訂閱狀態 + 三模式資料統計
                Section {
                    settingsHeroCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .opacity(heroCardAppeared ? 1 : 0)
                        .offset(y: heroCardAppeared ? 0 : 22)
                        .onAppear {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                                heroCardAppeared = true
                            }
                        }
                }
                disclosureBlock("訂閱方案", icon: "crown.fill", color: .yellow, isExpanded: $subscriptionExpanded) {
                    subscriptionSection
                }
                disclosureBlock("電子發票自動匯入", icon: "doc.text.viewfinder", color: .indigo, isExpanded: $einvoiceExpanded) {
                    einvoiceSection
                }
                disclosureBlock("自訂幣別匯率", icon: "dollarsign.arrow.circlepath", color: .blue, isExpanded: $currencyExpanded) {
                    currencyRateSection
                }
                disclosureBlock("iCloud 同步", icon: "icloud.fill", color: .blue, isExpanded: $iCloudExpanded) {
                    iCloudSyncSection
                }
                disclosureBlock("語音 AI 助手", icon: "waveform", color: .purple, isExpanded: $aiExpanded) {
                    aiAssistantSection
                }
                disclosureBlock("資料匯出 / 匯入", icon: "tray.and.arrow.up.fill", color: .green, isExpanded: $dataManagementExpanded) {
                    dataManagementSection
                }
                disclosureBlock("資料統計", icon: "chart.bar.fill", color: .orange, isExpanded: $dataStatsExpanded) {
                    dataStatsSection
                }
                disclosureBlock("自動備份還原", icon: "clock.arrow.circlepath", color: .teal, isExpanded: $restoreExpanded) {
                    restoreSection
                }
                // 危險區一律外露不收合，避免使用者誤觸或找不到
                dangerZoneSection
                disclosureBlock("關於", icon: "info.circle.fill", color: .gray, isExpanded: $aboutExpanded) {
                    aboutSection
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subscription)
            }
            // 匯出分享
            .sheet(item: $activeShareItem) { item in
                ShareSheet(items: [item.url])
            }
            // 隱藏管理控制台
            .sheet(isPresented: $showAdminConsole) {
                AdminConsoleView()
            }
            // 匯出錯誤
            .alert("匯出失敗", isPresented: $showExportError) {
                Button("確定") {}
            } message: {
                Text(exportErrorMessage)
            }
            // 匯入
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, UTType(filenameExtension: FullBackup.fileExtension) ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            // 匯入模式選擇
            .alert("匯入模式", isPresented: $showImportModeAlert) {
                Button("合併（保留現有資料）") {
                    performImport(mode: .merge)
                }
                Button("取代（覆蓋全部資料）", role: .destructive) {
                    performImport(mode: .replace)
                }
                Button("取消", role: .cancel) {
                    pendingImportData = nil
                    if let u = pendingBackupURL { try? FileManager.default.removeItem(at: u) }
                    pendingBackupURL = nil
                }
            } message: {
                Text("請選擇匯入方式。合併會跳過已存在的紀錄；取代會刪除現有資料並以匯入檔案覆蓋。")
            }
            // 匯入結果
            .alert("匯入結果", isPresented: $showImportResult) {
                Button("確定") {}
            } message: {
                Text(importResultMessage)
            }
            // 清除確認
            .alert("確定要清除所有資料嗎？", isPresented: $showClearConfirm) {
                Button("清除全部", role: .destructive) {
                    store.clearAll()
                    financeStore.clearAll()
                    lifeStore.clearAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作無法復原，所有三個模式的資料將被永久刪除。建議先匯出備份再進行清除。")
            }
            // 復原確認
            .alert("確定要復原資料嗎？", isPresented: $showRestoreConfirm) {
                Button("復原", role: .destructive) { performRestore() }
                Button("取消", role: .cancel) {}
            } message: {
                if let candidate = restoreCandidate {
                    Text("將復原至 \(formatRestoreDate(candidate.date)) 的資料快照。目前的所有資料將被覆蓋。")
                }
            }
            // 復原結果
            .alert("復原結果", isPresented: $showRestoreResult) {
                Button("確定") {}
            } message: {
                Text(restoreResultMessage)
            }
        }
    }

    // MARK: - 設定英雄卡片（訂閱狀態 + 三模式資料統計）

    private var settingsHeroCard: some View {
        VStack(spacing: 0) {
            // 頂部：方案名稱 + 版本 + 皇冠 / 鎖圖示
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(subscription.isPremium ? "Premium 訂閱中" : "免費版")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    Text("LifeGood")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("v\(appVersion)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(.top, 1)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 50, height: 50)
                    Image(systemName: subscription.isPremium ? "crown.fill" : "lock.open.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(subscription.isPremium
                                         ? Color(red: 1.0, green: 0.85, blue: 0.30)
                                         : .white.opacity(0.88))
                }
            }

            // 分隔線
            Rectangle()
                .fill(.white.opacity(0.20))
                .frame(height: 0.5)
                .padding(.vertical, 14)

            // 三模式 KPI 橫列
            HStack(spacing: 0) {
                settingsHeroStatCell(
                    label: "記帳",
                    count: store.expenses.count + store.incomes.count
                )
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                settingsHeroStatCell(
                    label: "理財",
                    count: financeStore.insurances.count + financeStore.stocks.count
                           + financeStore.vehicles.count + financeStore.realEstates.count
                )
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 0.5, height: 28)
                settingsHeroStatCell(
                    label: "人生",
                    count: lifeStore.milestones.count + lifeStore.familyMembers.count
                )
            }
            .padding(.vertical, 8)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: subscription.isPremium
                        ? [Color(red: 0.16, green: 0.74, blue: 0.50),
                           Color(red: 0.07, green: 0.50, blue: 0.38)]
                        : [Color(red: 0.38, green: 0.28, blue: 0.82),
                           Color(red: 0.22, green: 0.14, blue: 0.60)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // 右上主散景圓
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 140, height: 140)
                    .offset(x: 90, y: -55)
                    .blur(radius: 14)
                // 左下補光
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: 50)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
            color: (subscription.isPremium
                ? Color(red: 0.07, green: 0.50, blue: 0.38)
                : Color(red: 0.22, green: 0.14, blue: 0.60)).opacity(0.42),
            radius: 16, x: 0, y: 8
        )
    }

    /// KPI 統計格（供英雄卡 KPI 橫列使用）
    private func settingsHeroStatCell(label: String, count: Int) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text("\(count)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .contentTransition(.numericText())
            Text("筆")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    // MARK: - 訂閱

    private var subscriptionSection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("方案")
                        Text(subscription.currentPlanText)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: subscription.isPremium ? "checkmark.seal.fill" : "sparkles")
                        .foregroundStyle(subscription.isPremium ? .green : .orange)
                }
                Spacer()
                if subscription.isPremium {
                    Text("已訂閱")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))
                } else {
                    Button("升級") { showPaywall = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.green)
                }
            }

            if let exp = subscription.expirationText {
                HStack {
                    Label(exp, systemImage: "calendar")
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                Task { await subscription.restorePurchases() }
            } label: {
                settingsActionRow(
                    icon: "arrow.clockwise",
                    color: .blue,
                    title: "還原購買",
                    subtitle: "重新驗證已購買的訂閱方案"
                )
            }
            .foregroundStyle(.primary)

            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link(destination: url) {
                    settingsActionRow(
                        icon: "creditcard.fill",
                        color: .indigo,
                        title: "管理訂閱（App Store）",
                        subtitle: "取消或變更訂閱方案"
                    )
                }
            }

            #if DEBUG
            Toggle(isOn: Binding(
                get: { subscription.devOverride },
                set: { subscription.devOverride = $0 }
            )) {
                Label("開發者模式（強制解鎖）", systemImage: "hammer.fill")
                    .foregroundStyle(.orange)
            }
            #endif
        } header: {
            Text("訂閱")
        } footer: {
            Text("免費版可使用記帳全部功能與理財模式的「股票」管理。訂閱後解鎖儲蓄險、載具、房地產、人生履歷、家庭、管理等完整功能。\(FeatureGate.viewOnlyMessage)：未訂閱時其他功能仍可閱覽，但無法新增 / 編輯 / 刪除。")
        }
    }

    // MARK: - 電子發票自動匯入

    private var einvoiceSection: some View {
        Section {
            NavigationLink(destination: EInvoiceSetupView()) {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("電子發票自動匯入")
                            Text(einvoiceSync.isLinked
                                 ? "已連結 \(einvoiceSync.carrier?.cardNo ?? "")"
                                 : "連結手機條碼自動讀取消費")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: einvoiceSync.isLinked
                              ? "checkmark.seal.fill" : "qrcode")
                            .foregroundStyle(einvoiceSync.isLinked ? .green : .blue)
                    }
                    Spacer()
                    if einvoiceSync.isLinked {
                        Text("\(einvoiceSync.importHistory.count) 筆")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("電子發票")
        } footer: {
            Text("透過財政部電子發票 API 自動匯入消費紀錄到變動支出，並依商家自動分類。資料只存在本機，LifeGood 不會上傳任何資料到自有伺服器。")
        }
    }

    // MARK: - DisclosureGroup 包裝

    @ViewBuilder
    private func disclosureBlock<Content: View>(
        _ title: String,
        icon: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: isExpanded) {
                content()
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 2)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 手動設定匯率

    private var currencyRateSection: some View {
        Section {
            ForEach($store.currencyRates) { $rate in
                HStack(spacing: 8) {
                    TextField("幣別", text: $rate.code)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("=")
                        .foregroundStyle(.secondary)
                    TextField("比值", value: $rate.rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    Text("元")
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        store.currencyRates.removeAll { $0.id == rate.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                store.currencyRates.append(CurrencyRate())
            } label: {
                Label("新增匯率", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("手動設定匯率")
        } footer: {
            Text("輸入幣別代號與對 NT$ 的比值（例：美金 = 32 元）。新增後，記帳的金額輸入欄位左側即可選擇該幣別，輸入金額時將自動換算為 NT$。")
        }
    }

    // MARK: - iCloud 同步

    private var iCloudSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { cloudSync.isEnabled },
                set: { cloudSync.isEnabled = $0 }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("啟用 iCloud 同步")
                        Text("相同 Apple ID 裝置間自動同步")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.blue)
                }
            }
            .disabled(!cloudSync.isAccountAvailable)

            HStack {
                Label("iCloud 帳號", systemImage: cloudSync.isAccountAvailable ? "checkmark.icloud.fill" : "xmark.icloud.fill")
                    .foregroundStyle(cloudSync.isAccountAvailable ? Color.green : Color.red)
                Spacer()
                Text(cloudSync.isAccountAvailable ? "已登入" : "未登入")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cloudSync.isAccountAvailable ? Color.green : Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((cloudSync.isAccountAvailable ? Color.green : Color.red).opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke((cloudSync.isAccountAvailable ? Color.green : Color.red).opacity(0.22), lineWidth: 0.6))
            }

            HStack {
                Label("同步狀態", systemImage: syncStatusIcon)
                    .foregroundStyle(syncStatusColor)
                Spacer()
                Text(syncStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(syncStatusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(syncStatusColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(syncStatusColor.opacity(0.22), lineWidth: 0.6))
            }

            HStack {
                Label("最近同步", systemImage: "clock")
                Spacer()
                if let date = cloudSync.lastSyncDate {
                    Text(formatSyncDate(date))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.blue.opacity(0.18), lineWidth: 0.6))
                } else {
                    Text("尚未同步")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }

            if cloudSync.lastChangeReason != .none {
                HStack {
                    Label("最近事件", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(cloudSync.lastChangeReason.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }

            if let err = cloudSync.lastErrorMessage {
                HStack(alignment: .top) {
                    Label("同步錯誤", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text(err)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.20), lineWidth: 0.6))
                        .multilineTextAlignment(.trailing)
                }
            }

            Button {
                cloudSync.syncNow()
            } label: {
                settingsActionRow(
                    icon: "arrow.clockwise.icloud",
                    color: cloudSync.isAccountAvailable && cloudSync.isEnabled ? .blue : .secondary,
                    title: "立即同步",
                    subtitle: "手動觸發 iCloud 資料同步"
                )
            }
            .disabled(!cloudSync.isAccountAvailable || !cloudSync.isEnabled)

            Button {
                cloudSync.repromptInitialSync()
            } label: {
                settingsActionRow(
                    icon: "arrow.triangle.merge",
                    color: cloudSync.isAccountAvailable && cloudSync.isEnabled ? .teal : .secondary,
                    title: "重新選擇同步方式",
                    subtitle: "重新設定本機與雲端的整合方式"
                )
            }
            .disabled(!cloudSync.isAccountAvailable || !cloudSync.isEnabled)
        } header: {
            Text("iCloud 同步")
        } footer: {
            Text("啟用後，記帳/理財/人生三模式的資料會透過 iCloud 在相同 Apple ID 的裝置間自動同步。資料完全儲存於你的 iCloud，LifeGood 不會收集或上傳任何資料。未登入 iCloud 帳號時無法啟用。")
        }
        .confirmationDialog(
            "iCloud 已有資料",
            isPresented: Binding(
                get: { cloudSync.pendingInitialSync != nil },
                set: { newVal in
                    // 點擊外部關閉（仍處於待決狀態）→ 視為取消、關回開關
                    if !newVal, cloudSync.pendingInitialSync != nil { cloudSync.cancelInitialSync() }
                }
            ),
            titleVisibility: .visible,
            presenting: cloudSync.pendingInitialSync
        ) { _ in
            Button("以這台覆蓋雲端", role: .destructive) { cloudSync.resolveInitialSync(.overwriteCloud) }
            Button("以雲端覆蓋這台", role: .destructive) { cloudSync.resolveInitialSync(.overwriteLocal) }
            Button("合併（重複以本機為準）") { cloudSync.resolveInitialSync(.mergeLocalWins) }
            Button("合併（重複以雲端為準）") { cloudSync.resolveInitialSync(.mergeCloudWins) }
            Button("取消", role: .cancel) { cloudSync.cancelInitialSync() }
        } message: { info in
            Text("iCloud 目前約有 \(info.cloudItemCount) 筆資料。要如何與這台裝置的資料整合？\n\n・覆蓋會清掉其中一邊\n・合併會保留兩邊，重複的依你選的為準")
        }
    }

    private var syncStatusIcon: String {
        if !cloudSync.isAccountAvailable { return "icloud.slash" }
        if !cloudSync.isEnabled { return "pause.circle" }
        return "checkmark.circle.fill"
    }

    private var syncStatusColor: Color {
        if !cloudSync.isAccountAvailable { return .red }
        if !cloudSync.isEnabled { return .secondary }
        return .green
    }

    private var syncStatusText: String {
        if !cloudSync.isAccountAvailable { return "iCloud 未登入" }
        if !cloudSync.isEnabled { return "已關閉" }
        return "已同步"
    }

    private static let syncDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private func formatSyncDate(_ date: Date) -> String {
        Self.syncDateFormatter.string(from: date)
    }

    // MARK: - 語音 AI 助手

    @ViewBuilder
    private var aiAssistantSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("啟用後，變動支出頁面下方會出現麥克風按鈕，長按說話即可由 AI 自動建立記帳。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("語音辨識在裝置上完成；文字內容會送到你選的 AI 服務做欄位抽取。API Key 只存在這支手機的 Keychain，不會經過 LifeGood 伺服器。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        Section {
            Picker("使用中的 AI 服務", selection: Binding(
                get: { aiSettings.activeProvider?.rawValue ?? "" },
                set: { aiSettings.activeProvider = AIProvider(rawValue: $0) }
            )) {
                Text("停用").tag("")
                ForEach(AIProvider.allCases) { p in
                    Label(p.displayName, systemImage: p.icon).tag(p.rawValue)
                }
            }
        } header: {
            Text("供應商").textCase(.none)
        }

        ForEach(AIProvider.allCases) { p in
            providerKeySection(p)
        }
    }

    @ViewBuilder
    private func providerKeySection(_ p: AIProvider) -> some View {
        Section {
            HStack {
                Image(systemName: p.icon).foregroundStyle(.purple)
                Text(p.displayName).font(.subheadline.weight(.semibold))
                Spacer()
                if !aiSettings.key(for: p).isEmpty {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            SecureField("API Key", text: Binding(
                get: { aiSettings.key(for: p) },
                set: { aiSettings.setKey($0, for: p) }
            ))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .autocorrectionDisabled()
            if let consoleURL = URL(string: p.consoleURL) {
                Link(destination: consoleURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari.fill").font(.caption)
                        Text("前往 \(p.displayName) Console 取得 Key").font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
        } footer: {
            Text(p.helpText).font(.caption2)
        }
    }

    // MARK: - 資料管理

    private var dataManagementSection: some View {
        Section {
            // 匯出 JSON
            Button {
                exportJSON()
            } label: {
                settingsActionRow(
                    icon: "square.and.arrow.up",
                    color: .green,
                    title: "匯出 JSON",
                    subtitle: "完整資料備份，可重新匯入"
                )
            }
            .foregroundStyle(.primary)

            // 完整備份（含照片 / 文件）
            Button {
                exportFullBackup()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.teal.opacity(0.22), Color.teal.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.teal.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.teal)
                    }
                    .shadow(color: Color.teal.opacity(0.15), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("完整備份（含照片）")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if backupBusy { ProgressView().scaleEffect(0.7) }
                        }
                        Text("單一檔 .lifegood，含所有照片與文件，可重新匯入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .disabled(backupBusy)

            // 匯出 CSV
            Button {
                exportCSV()
            } label: {
                settingsActionRow(
                    icon: "tablecells",
                    color: .mint,
                    title: "匯出 CSV",
                    subtitle: "可用 Excel 或 Numbers 開啟"
                )
            }
            .foregroundStyle(.primary)

            // 匯出部屬資料（含班表 / 任務 / 會議 / 請假）
            Button {
                exportSubordinates()
            } label: {
                settingsActionRow(
                    icon: "person.2.fill",
                    color: .indigo,
                    title: "匯出部屬資料",
                    subtitle: "僅部屬，含班表/任務/會議/請假，可合併匯入"
                )
            }
            .foregroundStyle(.primary)

            // 匯入
            Button {
                showImporter = true
            } label: {
                settingsActionRow(
                    icon: "square.and.arrow.down",
                    color: .blue,
                    title: "匯入資料",
                    subtitle: "從 JSON 備份檔案匯入（自動辨識完整備份或部屬資料）"
                )
            }
            .foregroundStyle(.primary)
        } header: {
            Text("資料管理")
        } footer: {
            Text("「匯出 JSON」會一次包含記帳/理財/人生三模式的完整資料；「匯出部屬資料」只含部屬（連同班表、任務、會議、請假紀錄），方便單獨在裝置間搬移。匯入時會自動辨識檔案類型，可選擇合併或取代。")
        }
    }

    // MARK: - 資料統計

    private var dataStatsSection: some View {
        Section {
            // 三模式統計徽章：橫向卡片排列（v2: 各自錯開進場動畫）
            HStack(spacing: 10) {
                dataStatBadge(
                    icon: "yensign.circle.fill",
                    color: .green,
                    count: store.expenses.count + store.incomes.count,
                    label: "記帳"
                )
                .opacity(dataStatBadgesAppeared[0] ? 1 : 0)
                .offset(y: dataStatBadgesAppeared[0] ? 0 : 18)
                dataStatBadge(
                    icon: "chart.pie.fill",
                    color: .blue,
                    count: financeStore.insurances.count + financeStore.stocks.count +
                           financeStore.vehicles.count + financeStore.realEstates.count,
                    label: "理財"
                )
                .opacity(dataStatBadgesAppeared[1] ? 1 : 0)
                .offset(y: dataStatBadgesAppeared[1] ? 0 : 18)
                dataStatBadge(
                    icon: "star.circle.fill",
                    color: .orange,
                    count: lifeStore.milestones.count + lifeStore.familyMembers.count,
                    label: "人生"
                )
                .opacity(dataStatBadgesAppeared[2] ? 1 : 0)
                .offset(y: dataStatBadgesAppeared[2] ? 0 : 18)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .listRowBackground(Color(.systemGroupedBackground))
            .listRowSeparator(.hidden)
            .onAppear {
                dataStatBadgesAppeared = [false, false, false]
                for i in 0..<3 {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.72).delay(0.08 + Double(i) * 0.07)) {
                        dataStatBadgesAppeared[i] = true
                    }
                }
            }

            // 支出記錄時間區間（若有資料）
            let expDates = store.expenses.map(\.date)
            if let earliest = expDates.min(), let latest = expDates.max() {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("支出記錄區間")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatDate(earliest))  →  \(formatDate(latest))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("資料統計")
        }
    }

    private func dataStatBadge(icon: String, color: Color, count: Int, label: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("筆")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            ZStack {
                Color(.systemBackground)
                color.opacity(0.028)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.12), lineWidth: 0.75)
        )
        .shadow(color: color.opacity(0.12), radius: 6, x: 0, y: 2)
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    // MARK: - 復原資料

    private var restoreSection: some View {
        Section {
            Button {
                restoreCandidate = BackupManager.shared.findRestoreCandidate()
                if restoreCandidate != nil {
                    showRestoreConfirm = true
                } else {
                    restoreResultMessage = "目前沒有一小時前的資料快照可供復原。系統會在使用 App 時自動建立快照（間隔約 10 分鐘）。"
                    showRestoreResult = true
                }
            } label: {
                settingsActionRow(
                    icon: "clock.arrow.circlepath",
                    color: .orange,
                    title: "復原一小時前的資料",
                    subtitle: restoreCandidate.map { "可用快照：\(formatRestoreDate($0.date))" } ?? "尚無可用的快照"
                )
            }
            .foregroundStyle(.primary)
            .onAppear {
                // 預先查詢，避免在 label closure（每次 render）執行 filesystem I/O
                restoreCandidate = BackupManager.shared.findRestoreCandidate()
            }
        } header: {
            Text("資料復原")
        } footer: {
            Text("App 會自動建立資料快照（每 10 分鐘一次，保留 24 小時）。復原後目前的資料將被覆蓋為快照時的狀態。")
        }
    }

    private func performRestore() {
        guard let candidate = restoreCandidate else { return }
        // 復原前先建立一份當前快照，以防誤操作
        BackupManager.shared.createSnapshot(expense: store, finance: financeStore, life: lifeStore)
        let success = BackupManager.shared.restore(
            from: candidate.url,
            expense: store, finance: financeStore, life: lifeStore
        )
        restoreResultMessage = success
            ? "已成功復原至 \(formatRestoreDate(candidate.date)) 的資料。"
            : "復原失敗，快照資料可能已損壞。"
        showRestoreResult = true
    }

    private static let restoreDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d HH:mm"; return f
    }()
    private func formatRestoreDate(_ date: Date) -> String {
        Self.restoreDateFormatter.string(from: date)
    }

    // MARK: - 危險區域

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清除所有資料", systemImage: "trash")
            }
            .disabled(isAllDataEmpty)
        } header: {
            Text("危險操作")
        } footer: {
            Text("清除後無法復原，所有三個模式的資料都會被刪除，請先匯出備份。")
        }
    }

    private var isAllDataEmpty: Bool {
        store.expenses.isEmpty && store.incomes.isEmpty &&
        financeStore.insurances.isEmpty && financeStore.stocks.isEmpty &&
        financeStore.vehicles.isEmpty && financeStore.realEstates.isEmpty &&
        lifeStore.milestones.isEmpty && lifeStore.relationships.isEmpty &&
        lifeStore.pets.isEmpty && lifeStore.schedules.isEmpty
    }

    // MARK: - 行動列輔助（v3：36pt 漸層圖示圓 + 雙行文字）

    private func settingsActionRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 1)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            .shadow(color: color.opacity(0.15), radius: 4, x: 0, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 關於

    private var aboutSection: some View {
        Section {
            // 品牌識別卡
            VStack(spacing: 0) {
                // 上半：圖示 + 名稱
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.74, blue: 0.50),
                                        Color(red: 0.07, green: 0.50, blue: 0.38)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(
                                color: Color(red: 0.07, green: 0.50, blue: 0.38).opacity(0.38),
                                radius: 12, x: 0, y: 6
                            )
                        // 裝飾散景
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 36, height: 36)
                            .offset(x: 14, y: -14)
                            .blur(radius: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 5) {
                        Text("LifeGood")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("美好人生記實")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                // 三欄版本資訊
                Rectangle()
                    .fill(Color(.separator).opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.horizontal, 8)

                HStack(spacing: 0) {
                    aboutInfoCell(icon: "number", label: "版本", value: appVersion, color: .green)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 0.5, height: 48)
                    aboutInfoCell(icon: "hammer.fill", label: "Build", value: appBuild, color: .orange)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 0.5, height: 48)
                    aboutInfoCell(icon: "iphone", label: "最低需求", value: "iOS 17", color: .blue)
                }
                .padding(.vertical, 8)

                // 對外人數（達門檻才顯示）
                if remoteAdmin.shouldShowPublicCount {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(height: 0.5)
                        .padding(.horizontal, 8)
                    Text("已有 \(remoteAdmin.userCount) 位使用者一起記錄美好人生")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { handleAboutTap() }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemBackground))
        } header: {
            Text("關於")
        } footer: {
            HStack {
                Spacer()
                Text("© 2024–2026 LifeGood · 資料僅存於本機與您的 iCloud")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func aboutInfoCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - 匯出

    private func exportJSON() {
        let data = UnifiedExporter.exportJSON(expense: store, finance: financeStore, life: lifeStore)
        let filename = "LifeGood_\(dateStamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            activeShareItem = .json(url)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func exportCSV() {
        let csv = UnifiedExporter.exportCSV(expense: store, finance: financeStore, life: lifeStore)
        let filename = "LifeGood_\(dateStamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            activeShareItem = .csv(url)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func exportSubordinates() {
        let data = SubordinateExporter.exportJSON(life: lifeStore)
        let filename = "LifeGood_部屬_\(dateStamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            activeShareItem = .json(url)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    /// 完整備份（含照片 / 文件）：結構化資料在主執行緒準備，檔案 I/O 丟背景，避免卡 UI。
    private func exportFullBackup() {
        backupBusy = true
        ExportProgressModel.shared.isExporting = true
        ExportProgressModel.shared.fraction = 0
        let unified = UnifiedExport.build(expense: store, finance: financeStore, life: lifeStore)
        Task.detached {
            do {
                let url = try FullBackup.export(unified: unified) { f in
                    Task { @MainActor in ExportProgressModel.shared.update(f) }
                }
                await MainActor.run {
                    ExportProgressModel.shared.finish()
                    activeShareItem = .backup(url); backupBusy = false
                }
            } catch {
                await MainActor.run {
                    ExportProgressModel.shared.isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                    backupBusy = false
                }
            }
        }
    }

    // MARK: - 匯入

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importResultMessage = "無法存取選取的檔案"
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                if FullBackup.isBackupFile(url: url) {
                    // 完整備份檔可能很大 → 複製到暫存後串流還原，不整檔讀進記憶體
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("import_\(UUID().uuidString).\(FullBackup.fileExtension)")
                    try? FileManager.default.removeItem(at: tmp)
                    try FileManager.default.copyItem(at: url, to: tmp)
                    pendingBackupURL = tmp
                    showImportModeAlert = true
                } else {
                    let data = try Data(contentsOf: url)
                    pendingImportData = data
                    showImportModeAlert = true
                }
            } catch {
                importResultMessage = "讀取檔案失敗：\(error.localizedDescription)"
                showImportResult = true
            }
        case .failure(let error):
            importResultMessage = "選取檔案失敗：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    private func performImport(mode: UnifiedImporter.Mode) {
        // 完整備份檔（含照片）
        if let backupURL = pendingBackupURL {
            do {
                let summary = try FullBackup.restore(from: backupURL, mode: mode,
                                                     expense: store, finance: financeStore, life: lifeStore)
                importResultMessage = (mode == .merge ? "已合併匯入完整備份：" : "已取代為完整備份：") + summary
            } catch {
                importResultMessage = "完整備份匯入失敗：\(error.localizedDescription)"
            }
            try? FileManager.default.removeItem(at: backupURL)
            pendingBackupURL = nil
            showImportResult = true
            return
        }
        guard let data = pendingImportData else { return }
        // 自動辨識：部屬資料檔走部屬匯入，否則走三模式完整匯入
        if SubordinateImporter.isSubordinateExport(data) {
            let r = SubordinateImporter.importData(data: data, mode: mode, life: lifeStore)
            importResultMessage = (mode == .merge ? "已合併匯入部屬資料：" : "已取代部屬資料：") + r.summary
        } else {
            let result = UnifiedImporter.importData(
                data: data, mode: mode,
                expense: store, finance: financeStore, life: lifeStore
            )
            switch mode {
            case .merge:
                importResultMessage = "成功合併匯入：\(result.summary)"
            case .replace:
                importResultMessage = "已取代為匯入資料：\(result.summary)"
            }
        }
        pendingImportData = nil
        showImportResult = true
    }

    // MARK: - Helpers

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f
    }()
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f
    }()

    private func dateStamp() -> String { Self.dateStampFormatter.string(from: Date()) }
    private func formatDate(_ date: Date) -> String { Self.shortDateFormatter.string(from: date) }

    /// 關於頁連點計數：累積 20 下開啟隱藏管理控制台
    private func handleAboutTap() {
        aboutTapCount += 1
        if aboutTapCount >= 20 {
            aboutTapCount = 0
            showAdminConsole = true
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ExpenseStore())
        .environmentObject(FinanceStore())
        .environmentObject(LifeStore())
        .environmentObject(CloudSyncManager.shared)
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(EInvoiceSyncManager.shared)
}
