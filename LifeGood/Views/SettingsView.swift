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
// [2026-06] v4 美化方向：
//  10. settingsHeroCard 背景：補第三顆散景圓（55pt, white.opacity(0.06), offset x:30 y:42, blur 8）
//      + 頂部玻璃光澤（LinearGradient [.white.opacity(0.18),.clear] top→center），
//      對齊 OverviewView.monthlyBalanceCard v3/v4 / IncomeView v4 / VariableExpenseView v4
//      英雄卡三圓+玻璃光澤規格，消除 settingsHeroCard 是全 App 唯一缺漏兩層裝飾的視覺不均衡。
//  11. settingsHeroCard KPI 橫列 padding：.vertical 8 → 10 + background opacity 0.10 → 0.08，
//      對齊 OverviewView / IncomeView / VariableExpenseView KPI 橫列標準規格。
//  12. settingsHeroStatCell count Text：補 lineLimit(1) + minimumScaleFactor(0.75)，
//      防止筆數過多時數字換行，對齊全 App kpiCell 防截斷規格。
//  13. aboutInfoCell 圖示圓：32pt pure fill(0.12) → 34pt LinearGradient(0.20→0.08) +
//      Circle().stroke(color.opacity(0.18), 0.75pt)，對齊 OverviewView.summaryCard v3 /
//      FinanceOverviewView.assetCard v3 / CareerView v3 圖示圓規格，補齊「關於」欄唯一
//      未升級的圖示圓視覺落差。
// [2026-07 v5] currencyRateSection 補齊空狀態 + 列樣式一致性（此段是全檔案唯一
//      仍停留在「純 TextField 裸排」、從未跟上其他小節視覺規格的區塊）：
//  14. 新增空狀態：尚未設定任何匯率時顯示 emptyCurrencyRow（圖示 + 文字），
//      對齊 HealthProfileEditView.emptyRow 的 Form Section 內緊湊空狀態規格，
//      避免只剩一顆「新增匯率」按鈕孤立顯示、使用者不清楚此區用途。
//  15. 幣別列補上 22pt 漸層小圖示圓（globe），比值欄位改用 monospacedDigit，
//      對齊全 App 數字欄位等寬對齊慣例，避免多筆匯率上下數字左右跳動。
// [2026-07 v6] providerKeySection 圖示圓升級（承接 v5 breadcrumb）：
//  16. 供應商列圖示：裸 Image(systemName:) → 22pt 漸層圖示圓，對齊 currencyRateSection
//      幣別列規格；已設定 Key 狀態：孤立 checkmark.seal.fill → 綠色「已設定」Capsule 徽章，
//      對齊 subscriptionSection「已訂閱」／iCloudSyncSection「已登入」既有徽章規格。
//      純視覺加強，未動 API Key 讀寫、Keychain 儲存或啟用中服務判斷邏輯。
// [2026-07 v7] aiAssistantSection 說明區塊補齊圖示錨點（承接 v6 breadcrumb）：
//  17. 頂部麥克風/隱私說明兩行文字原本純 Text 裸排、無任何圖示，是本檔案唯一沒有圖示
//      錨點的內容區塊；補上 22pt 漸層圖示圓（waveform，紫色），對齊緊接在後的
//      providerKeySection 供應商列圖示規格，讓「AI 語音記帳」整組區塊（說明 + 供應商 +
//      各供應商 Key 列）圖示語言一致。純視覺調整，未動語音辨識／AI 欄位抽取邏輯。
// [2026-07 v8] 「使用中的 AI 服務」Picker 補齊圖示錨點（承接 v7 breadcrumb）：
//  18. Picker 原本是純文字裸排選單，是 aiAssistantSection 中唯一沒有圖示錨點的列；
//      改用自訂 label（22pt 漸層圖示圓 + 文字），圖示隨目前啟用中的供應商動態切換
//      （p.icon），停用時顯示中性 poweroff，對齊緊接在後 providerKeySection 供應商列
//      的圖示圓規格。純視覺調整，selection binding／AIProvider 判斷邏輯完全未變動。
// [2026-07 v9] dataStatsSection「支出記錄區間」列圖示圓升級（承接 v8 breadcrumb）：
//  19. 該列圖示原本是 32pt 純 fill(0.12)、全檔案圖示圓唯一未套用 LinearGradient +
//      stroke 的殘留位置；改為 36pt LinearGradient(0.22→0.09) + Circle().stroke(0.20, 1pt)
//      + shadow，對齊同結構（icon + 標題/副標 + Spacer）的 settingsActionRow 規格。
//      純視覺調整，日期區間計算與顯示文字完全未變動。
//      （SettingsView 全檔案圖示圓規格至此已收斂一致；下次美化本檔案時可轉往複查各
//        Section footer 說明文字的字級／行距是否有落差，或改往其他仍有未收斂圖示圓
//        殘留的畫面）
// [2026-07 v10] providerKeySection footer 字級落差修復（承接 v9 breadcrumb 指出的
//      「複查各 Section footer 字級是否有落差」）：
//  20. p.helpText（各 AI 供應商申請 Key 教學＋額外扣款警語）先前額外覆寫
//      .font(.caption2)，是全檔案 10 處 Section footer 中唯一縮小字級的一處，
//      比 dataStatsSection／iCloudSyncSection／currencyRateSection 等其餘說明性
//      footer 使用的系統預設 .footnote 更小，內容又包含金額扣款資訊，字級不該是
//      全頁最小。移除該覆寫，改回與其餘 9 處一致的預設 footer 字級；「關於」區
//      版權宣告（1431 行）字體較小、置中、.tertiary 色，屬刻意的小字版權印刷慣例，
//      與說明性 footer 是不同類別，不在此次調整範圍。純文字字級調整，
//      helpText 內容、Provider 選擇、Key 讀寫等既有商業邏輯完全未變動。
// [2026-08 v11] dataManagementSection「載入狀態」補漏（匯出 JSON／CSV／部屬資料三顆按鈕）：
//  21. 三顆按鈕點下後都會經 Task.detached 背景寫檔（JSON 序列化＋寫入暫存檔），
//      期間只靠 .disabled(exportBusy) 讓按鈕變暗，同一 Section 緊接在後的「完整備份」
//      「一鍵壓縮」兩列卻各自有標題旁 ProgressView 進度提示——三顆匯出按鈕是本檔案
//      dataManagementSection 唯一沒有任何進行中回饋的列，容易讓使用者誤以為沒反應而
//      重複點擊，造成分享面板重疊觸發。共用 settingsActionRow 新增 busy 參數（預設
//      false，其餘 5 個既有呼叫端不受影響），busy 時在標題旁顯示同色 ProgressView，
//      三顆按鈕改傳入 busy: exportBusy；並把「完整備份」「一鍵壓縮」原本未指定色調、
//      沿用系統藍的 ProgressView 補上 .tint(.teal) / .tint(.indigo)，與各自圖示圓主題色
//      對齊，避免五顆進度指示器裡有兩顆跟圖示脫色。純視覺層調整，
//      exportJSON()／exportCSV()／exportSubordinates() 等既有匯出邏輯與 exportBusy
//      互斥鎖完全未變動。
//      （下次美化本檔案時：可轉往其他仍留有待辦的畫面）

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

// MARK: - 完整備份：照片時間範圍選擇

struct BackupRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (ClosedRange<Date>?) -> Void

    @State private var option = 0   // 0 全部 / 1 最近一年 / 2 最近三年 / 3 自訂
    @State private var start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var end = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("照片範圍", selection: $option) {
                        Text("全部").tag(0)
                        Text("最近一年").tag(1)
                        Text("最近三年").tag(2)
                        Text("自訂").tag(3)
                    }
                    if option == 3 {
                        DatePicker("起", selection: $start, displayedComponents: .date)
                        DatePicker("訖", selection: $end, displayedComponents: .date)
                    }
                } header: {
                    Text("照片 / 文件時間範圍")
                } footer: {
                    Text("結構化資料一律完整備份；此範圍只用來篩選照片 / 文件以縮小檔案，依檔案時間判斷。")
                }
                Section {
                    Button {
                        onConfirm(resolvedRange())
                        dismiss()
                    } label: {
                        Label("開始完整備份", systemImage: "archivebox.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.green).bold()
                }
            }
            .navigationTitle("完整備份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func resolvedRange() -> ClosedRange<Date>? {
        let cal = Calendar.current
        switch option {
        case 1: return (cal.date(byAdding: .year, value: -1, to: Date()) ?? Date())...Date()
        case 2: return (cal.date(byAdding: .year, value: -3, to: Date()) ?? Date())...Date()
        case 3:
            let lo = cal.startOfDay(for: min(start, end))
            let hi = cal.date(bySettingHour: 23, minute: 59, second: 59, of: max(start, end)) ?? max(start, end)
            return lo...hi
        default: return nil
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
    // 匯出 JSON／CSV／部屬資料共用忙碌旗標：三者皆用 Task.detached 背景寫檔＋檔名含秒級 dateStamp()，
    // 沒有守衛時快速連點同一顆按鈕會並發跑兩個 Task 各自寫同一個檔名、各自把 activeShareItem 蓋過去，
    // 造成分享面板閃爍/重開，比照旁邊「完整備份」backupBusy 既有規格補上。
    @State private var exportBusy = false
    // 一鍵壓縮既有照片：busy 防連點 + 完成結果訊息
    @State private var compressBusy = false
    @State private var compressResultMessage: String?
    // 驗證雲端資料：busy 防連點 + 抽查結果
    @State private var verifyBusy = false
    @State private var verifyResultText: String?
    @State private var verifyResultIsError = false
    @State private var showBackupRange = false     // 完整備份的時間範圍選擇
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
                        .onDisappear {
                            heroCardAppeared = false
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
            // 完整備份：照片時間範圍選擇
            .sheet(isPresented: $showBackupRange) {
                BackupRangeSheet { range in
                    exportFullBackup(photoRange: range)
                }
                .presentationDetents([.height(360)])
            }
            // 匯出錯誤
            .alert("匯出失敗", isPresented: $showExportError) {
                Button("確定") {}
            } message: {
                Text(exportErrorMessage)
            }
            // 一鍵壓縮既有照片：完成結果
            .alert("照片壓縮完成", isPresented: Binding(
                get: { compressResultMessage != nil },
                set: { if !$0 { compressResultMessage = nil } }
            )) {
                Button("確定") { compressResultMessage = nil }
            } message: {
                Text(compressResultMessage ?? "")
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
                Text(restoreCandidate.map { "將復原至 \(formatRestoreDate($0.date)) 的資料快照。目前的所有資料將被覆蓋。" }
                     ?? "目前的所有資料將被覆蓋。")
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
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
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
                // [v4] 中右微光（第三顆散景圓），對齊 IncomeView / VariableExpenseView 三圓規格
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: 55, height: 55)
                    .offset(x: 30, y: 42)
                    .blur(radius: 8)
                // [v4] 頂部玻璃光澤，對齊全 App 英雄卡 glass shine 規格
                LinearGradient(
                    colors: [.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
            // 對齊 SubscriptionManager.restorePurchases() 新增的 restoreInProgress 守衛：
            // 連點時第一次請求還在跑就先鎖住按鈕，避免並發觸發多個 AppStore.sync()。
            .disabled(subscription.restoreInProgress)

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
            if store.currencyRates.isEmpty {
                emptyCurrencyRow
            }

            ForEach(store.currencyRates) { rate in
                CurrencyRateRow(rateId: rate.id, initialCode: rate.code, initialRate: rate.rate)
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

    /// 匯率清單空狀態（Form Section 內緊湊樣式），對齊 HealthProfileEditView.emptyRow 規格
    private var emptyCurrencyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("尚未設定自訂匯率")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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

            // 驗證雲端資料：直接向 iCloud 伺服器抽查（非本機宣稱），
            // 回報結構化資料筆數、最近照片抽查結果與伺服器端最後上雲時間
            Button {
                verifyCloudData()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.22), Color.cyan.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.cyan.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.cyan)
                    }
                    .shadow(color: Color.cyan.opacity(0.15), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("驗證雲端資料")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if verifyBusy { ProgressView().scaleEffect(0.7) }
                        }
                        Text("向 iCloud 伺服器抽查，確認資料真的在雲端")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .disabled(verifyBusy || !cloudSync.isAccountAvailable || !cloudSync.isEnabled)

            if let text = verifyResultText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(verifyResultIsError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
            // [v7] 說明區塊補 22pt 漸層圖示圓（waveform），對齊本區塊下方 providerKeySection
            // 供應商列既有的紫色圖示圓規格，消除本區塊原本是全 aiAssistantSection 唯一
            // 沒有任何圖示錨點、純文字裸排的視覺落差。
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.20), Color.purple.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                    Circle()
                        .stroke(Color.purple.opacity(0.20), lineWidth: 0.75)
                        .frame(width: 22, height: 22)
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("啟用後，變動支出頁面下方會出現麥克風按鈕，長按說話即可由 AI 自動建立記帳。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("語音辨識在裝置上完成；文字內容會送到你選的 AI 服務做欄位抽取。API Key 只存在這支手機的 Keychain，不會經過 LifeGood 伺服器。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
        }
        Section {
            // [v8] Picker 補 22pt 漸層圖示圓（隨目前啟用中的供應商變色圖示，
            // 停用時顯示中性 poweroff），對齊緊接在後的 providerKeySection 供應商列
            // 規格，消除本列原本是全 aiAssistantSection 唯一沒有圖示錨點的裸排選單。
            Picker(selection: Binding(
                get: { aiSettings.activeProvider?.rawValue ?? "" },
                set: { aiSettings.activeProvider = AIProvider(rawValue: $0) }
            )) {
                Text("停用").tag("")
                ForEach(AIProvider.allCases) { p in
                    Label(p.displayName, systemImage: p.icon).tag(p.rawValue)
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.20), Color.purple.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 22)
                        Circle()
                            .stroke(Color.purple.opacity(0.20), lineWidth: 0.75)
                            .frame(width: 22, height: 22)
                        Image(systemName: aiSettings.activeProvider?.icon ?? "poweroff")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    Text("使用中的 AI 服務")
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
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.20), Color.purple.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 22, height: 22)
                    Circle()
                        .stroke(Color.purple.opacity(0.20), lineWidth: 0.75)
                        .frame(width: 22, height: 22)
                    Image(systemName: p.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                Text(p.displayName).font(.subheadline.weight(.semibold))
                Spacer()
                if !aiSettings.key(for: p).isEmpty {
                    Text("已設定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.22), lineWidth: 0.6))
                }
            }
            ProviderAPIKeyField(provider: p, initialKey: aiSettings.key(for: p))
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
            Text(p.helpText)
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
                    subtitle: "完整資料備份，可重新匯入",
                    busy: exportBusy
                )
            }
            .foregroundStyle(.primary)
            .disabled(exportBusy)

            // 完整備份（含照片 / 文件）
            Button {
                showBackupRange = true
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
                            if backupBusy { ProgressView().scaleEffect(0.7).tint(.teal) }
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

            // 一鍵壓縮既有照片（新照片存檔時已自動壓縮；此工具處理歷史大圖）
            Button {
                recompressStoredPhotos()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.indigo.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.indigo)
                    }
                    .shadow(color: Color.indigo.opacity(0.15), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("一鍵壓縮既有照片")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if compressBusy { ProgressView().scaleEffect(0.7).tint(.indigo) }
                        }
                        Text("把過去存的大圖縮到 1080P JPEG 80%，縮小備份檔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .disabled(compressBusy)

            // 匯出 CSV
            Button {
                exportCSV()
            } label: {
                settingsActionRow(
                    icon: "tablecells",
                    color: .mint,
                    title: "匯出 CSV",
                    subtitle: "可用 Excel 或 Numbers 開啟",
                    busy: exportBusy
                )
            }
            .foregroundStyle(.primary)
            .disabled(exportBusy)

            // 匯出部屬資料（含班表 / 任務 / 會議 / 請假）
            Button {
                exportSubordinates()
            } label: {
                settingsActionRow(
                    icon: "person.2.fill",
                    color: .indigo,
                    title: "匯出部屬資料",
                    subtitle: "僅部屬，含班表/任務/會議/請假，可合併匯入",
                    busy: exportBusy
                )
            }
            .foregroundStyle(.primary)
            .disabled(exportBusy)

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
            // [2026-07 v9] 圖示圓 32pt 純 fill(0.12) → 36pt LinearGradient + stroke + shadow，
            // 對齊 settingsActionRow（icon + 標題/副標 + Spacer 同結構列）圖示圓規格。
            let expDates = store.expenses.map(\.date)
            if let earliest = expDates.min(), let latest = expDates.max() {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.22), Color.green.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.green.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .shadow(color: Color.green.opacity(0.15), radius: 4, x: 0, y: 2)
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
        // lifeStore.isEmpty 涵蓋 clearAll() 會清空的完整欄位清單（含 familyMembers／subordinates／
        // departments／businessCards／healthProfile 等），避免像先前只列舉 milestones/relationships/
        // pets/schedules 四類，漏掉其餘分類導致使用者明明有資料、按鈕卻被誤判為禁用。
        store.expenses.isEmpty && store.incomes.isEmpty &&
        financeStore.insurances.isEmpty && financeStore.stocks.isEmpty &&
        financeStore.vehicles.isEmpty && financeStore.realEstates.isEmpty &&
        lifeStore.isEmpty
    }

    // MARK: - 行動列輔助（v3：36pt 漸層圖示圓 + 雙行文字）

    // [v11] 新增 busy 參數（預設 false，既有 8 個呼叫端不受影響）：匯出 JSON／CSV／部屬資料
    // 三顆按鈕先前執行期間僅靠 .disabled(exportBusy) 讓按鈕變暗，同一 Section 緊接在後的
    // 「完整備份」「一鍵壓縮」兩列卻都有標題旁 ProgressView 進度提示，是本檔案「載入狀態」
    // 系列裡唯一沒跟上的三處——使用者點下去後看不到任何進行中回饋，容易誤以為沒反應而重複點擊。
    // 對齊既有 backupBusy／compressBusy 列規格，加上同色 ProgressView，busy 時機到才顯示，
    // 不影響其餘 5 個呼叫端外觀。
    private func settingsActionRow(icon: String, color: Color, title: String, subtitle: String, busy: Bool = false) -> some View {
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
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if busy { ProgressView().scaleEffect(0.7).tint(color) }
                }
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
                // [v4] 升級為 LinearGradient + stroke，對齊全 App 標準圖示圓規格
                Circle()
                    .fill(LinearGradient(
                        colors: [color.opacity(0.20), color.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 34, height: 34)
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 0.75)
                    .frame(width: 34, height: 34)
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

    // exportJSON／exportCSV／exportSubordinates：與 exportFullBackup 同一模式——只有讀取
    // @Published 屬性組出純 struct 快照這步留在主執行緒（很快），實際 JSON 編碼／CSV 組字串
    // 這種資料量大時會卡 UI 的重運算搬到背景執行緒，寫完檔再跳回主執行緒更新分享項目。

    /// 驗證雲端資料：向 iCloud 伺服器抽查 KVBlob／Photo 記錄是否存在。
    private func verifyCloudData() {
        guard !verifyBusy else { return }
        verifyBusy = true
        verifyResultText = nil
        CloudKitManager.shared.verifyCloudData(keys: CloudSyncManager.syncKeys) { result in
            verifyBusy = false
            if let err = result.errorMessage {
                verifyResultIsError = true
                verifyResultText = "驗證失敗：\(err)"
                return
            }
            verifyResultIsError = false
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_Hant_TW")
            fmt.dateFormat = "M/d HH:mm"
            var lines: [String] = []
            lines.append("結構化資料：雲端 \(result.kvFound)/\(result.kvTotal) 筆"
                         + (result.latestKVDate.map { "（最後上雲 \(fmt.string(from: $0))）" } ?? ""))
            if result.photoChecked > 0 {
                lines.append("抽查最近照片：雲端 \(result.photoFound)/\(result.photoChecked) 張"
                             + (result.latestPhotoDate.map { "（最後上雲 \(fmt.string(from: $0))）" } ?? ""))
            }
            if result.kvFound < result.kvTotal || result.photoFound < result.photoChecked {
                lines.append("有項目尚未上雲：請按「立即同步」後再驗證一次。")
            } else {
                lines.append("資料已確認在 iCloud 伺服器上。")
            }
            verifyResultText = lines.joined(separator: "\n")
        }
    }

    /// 一鍵壓縮既有照片：IO 密集，移到背景執行緒跑完再回主執行緒更新結果。
    private func recompressStoredPhotos() {
        guard !compressBusy else { return }
        compressBusy = true
        Task.detached(priority: .userInitiated) {
            let result = ImageCompressor.recompressAllStoredPhotos()
            await MainActor.run {
                compressBusy = false
                if result.scanned == 0 {
                    compressResultMessage = "沒有找到照片檔案。"
                } else if result.compressed == 0 {
                    compressResultMessage = "掃描 \(result.scanned) 張照片，全部已是壓縮尺寸，無需再處理。"
                } else {
                    compressResultMessage = String(
                        format: "掃描 %d 張、壓縮 %d 張，共省下 %.1f MB。",
                        result.scanned, result.compressed, result.savedMB
                    )
                }
            }
        }
    }

    private func exportJSON() {
        guard !exportBusy else { return }
        exportBusy = true
        let payload = UnifiedExport.build(expense: store, finance: financeStore, life: lifeStore)
        let filename = "LifeGood_\(dateStamp()).json"
        Task.detached {
            let data = UnifiedExporter.exportJSON(payload)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                await MainActor.run { activeShareItem = .json(url); exportBusy = false }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                    exportBusy = false
                }
            }
        }
    }

    private func exportCSV() {
        guard !exportBusy else { return }
        exportBusy = true
        let payload = UnifiedExport.build(expense: store, finance: financeStore, life: lifeStore)
        let filename = "LifeGood_\(dateStamp()).csv"
        Task.detached {
            let csv = UnifiedExporter.exportCSV(payload)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                await MainActor.run { activeShareItem = .csv(url); exportBusy = false }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                    exportBusy = false
                }
            }
        }
    }

    private func exportSubordinates() {
        guard !exportBusy else { return }
        exportBusy = true
        let payload = SubordinateExport(
            subordinates: lifeStore.subordinates,
            departments: lifeStore.departments,
            gradeTitles: lifeStore.gradeTitles
        )
        let filename = "LifeGood_部屬_\(dateStamp()).json"
        Task.detached {
            let data = SubordinateExporter.exportJSON(payload)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                await MainActor.run { activeShareItem = .json(url); exportBusy = false }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                    exportBusy = false
                }
            }
        }
    }

    /// 完整備份（含照片 / 文件）：結構化資料在主執行緒準備，檔案 I/O 丟背景，避免卡 UI。
    private func exportFullBackup(photoRange: ClosedRange<Date>?) {
        guard !backupBusy else { return }
        backupBusy = true
        ExportProgressModel.shared.isExporting = true
        ExportProgressModel.shared.fraction = 0
        let unified = UnifiedExport.build(expense: store, finance: financeStore, life: lifeStore)
        Task.detached {
            do {
                let url = try FullBackup.export(unified: unified, photoRange: photoRange) { f in
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

/// AI 供應商 API Key 欄位：SecureField 先前直接綁在 aiSettings.setKey(for:) 上，每敲一個字元
/// 都會同步寫入 Keychain 並讓 keyChangeStamp 遞增，觸發整個 SettingsView 重繪。對齊
/// CurrencyRateRow 既有修復規格：改為本地暫存文字，停止輸入 400ms 後才提交回 Keychain。
private struct ProviderAPIKeyField: View {
    let provider: AIProvider
    @State private var keyText: String
    @State private var commitTask: Task<Void, Never>?

    init(provider: AIProvider, initialKey: String) {
        self.provider = provider
        _keyText = State(initialValue: initialKey)
    }

    var body: some View {
        SecureField("API Key", text: $keyText)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .autocorrectionDisabled()
            .onChange(of: keyText) { _, _ in scheduleCommit() }
            .onDisappear {
                commitTask?.cancel()
                commit()
            }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        if AISettingsStore.shared.key(for: provider) != keyText {
            AISettingsStore.shared.setKey(keyText, for: provider)
        }
    }
}

/// 匯率列：TextField 先前直接綁在 $store.currencyRates[index] 上，每敲一個字元都會讓
/// ExpenseStore.currencyRates 的 didSet 觸發整份陣列重新編碼寫入 UserDefaults + CloudKit
/// pushAll 排程，且 @Published 變動會讓整個 SettingsView（含所有其他 disclosureBlock 區塊）
/// 跟著重繪。對齊 GradeTitleView.GradeTitleRow 既有修復規格：改為本地暫存文字/數值，
/// 停止輸入 400ms 後才提交回 store。
private struct CurrencyRateRow: View {
    @EnvironmentObject var store: ExpenseStore
    let rateId: UUID

    @State private var codeText: String
    @State private var rateValue: Double
    @State private var commitTask: Task<Void, Never>?

    init(rateId: UUID, initialCode: String, initialRate: Double) {
        self.rateId = rateId
        _codeText = State(initialValue: initialCode)
        _rateValue = State(initialValue: initialRate)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.20), Color.blue.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(Color.blue.opacity(0.20), lineWidth: 0.75)
                    .frame(width: 22, height: 22)
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            TextField("幣別", text: $codeText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: codeText) { _, _ in scheduleCommit() }
            Text("=")
                .foregroundStyle(.secondary)
            TextField("比值", value: $rateValue, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .default).monospacedDigit())
                .frame(maxWidth: 80)
                .onChange(of: rateValue) { _, _ in scheduleCommit() }
            Text("元")
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                commitTask?.cancel()
                store.currencyRates.removeAll { $0.id == rateId }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .onDisappear {
            commitTask?.cancel()
            commit()
        }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        guard let idx = store.currencyRates.firstIndex(where: { $0.id == rateId }) else { return }
        if store.currencyRates[idx].code != codeText { store.currencyRates[idx].code = codeText }
        if store.currencyRates[idx].rate != rateValue { store.currencyRates[idx].rate = rateValue }
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
