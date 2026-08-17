import SwiftUI
import UniformTypeIdentifiers
import CloudKit

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
// [2026-08 v12] 「驗證雲端資料」按鈕補齊 ProgressView 主題色（承接 v11 busy 指示器規格）：
//  22. v25.123 新增的「驗證雲端資料」列（cyan 主題，抽查 iCloud 伺服器確認資料真的上雲）
//      因未走共用 settingsActionRow（需額外顯示 verifyResultText 結果列），是自行刻的
//      HStack，複製了圖示圓／陰影樣式，卻漏了 v11 才補齊的 ProgressView 主題色規格——
//      是本檔案 4 處 busy ProgressView（backupBusy/.tint(.teal)、compressBusy/.tint(.indigo)、
//      settingsActionRow busy 參數/.tint(color)）中唯一沿用系統預設灰藍色、與自身 cyan
//      圖示圓／邊框脫色的一處。補上 .tint(.cyan)，四處進度指示器主題色至此全數對齊。
//      純視覺層調整，verifyCloudData()／verifyBusy 忙碌守衛等既有驗證邏輯完全未變動。
// [2026-08 v13] iCloudSyncSection「立即同步」列 ProgressView 補齊主題色（v12 複查遺漏的第 5 處）：
//  23. v12 筆記統計「4 處 busy ProgressView」並宣稱主題色已全數對齊，但複查發現「立即同步」
//      （cloudSync.isSyncing 期間顯示於「同步中…」文字旁）其實是本檔案第 5 處、也是唯一
//      仍沿用系統預設灰藍色的 ProgressView——因該列同樣未走共用 settingsActionRow（右側
//      多一顆「重置」逃生按鈕，需自行手刻 HStack），與 verifyBusy／diagBusy／backupBusy／
//      compressBusy 一樣容易被複查漏掉。補上 .tint(.blue)，對齊該列圖示圓（arrow.clockwise.
//      icloud，blue 主題）既有配色，SettingsView 全檔案 ProgressView 主題色至此才真正全數對齊
//      （共 6 處：diagBusy/.orange、verifyBusy/.cyan、backupBusy/.teal、compressBusy/.indigo、
//      settingsActionRow busy/依傳入 color、立即同步/.blue）。純視覺層調整，syncNow()／
//      forceResetSyncState() 等既有同步邏輯完全未變動。
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

    // 同步診斷：逐層測試（一般網路→帳號→讀→寫→zone），顯示每層原始錯誤碼
    @State private var diagBusy = false
    @State private var diagResultText: String?
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
    // 匯率自動更新
    @State private var isFetchingRates = false
    @State private var rateUpdateResult = ""
    @State private var rateRowsRefreshToken = 0
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
                // 進階設定：內建模板的可調參數（曲線點數／透明度等）集中在獨立頁
                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.gray.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("進階設定")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
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
                HeroKpiCell(label: "記帳",
                            value: "\(store.expenses.count + store.incomes.count) 筆",
                            icon: "list.bullet.rectangle.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "理財",
                            value: "\(financeStore.insurances.count + financeStore.stocks.count + financeStore.vehicles.count + financeStore.realEstates.count) 筆",
                            icon: "chart.pie.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "人生",
                            value: "\(lifeStore.milestones.count + lifeStore.familyMembers.count) 筆",
                            icon: "sparkles")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        // 這張卡的漸層依訂閱狀態切換（付費綠／未付費紫），所以走 runtimeColors——
        // 它插在出廠與單卡覆寫之間：使用者若在進階設定指定了顏色，那個顏色仍然優先。
        .heroCardShell(card: .settings,
                       runtimeColors: subscription.isPremium
                            ? HeroCard.settingsPremiumGradient
                            : HeroCard.settingsFreeGradient)
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

    // MARK: - 幣別匯率（手動輸入＋自動更新）

    private var currencyRateSection: some View {
        Section {
            if store.currencyRates.isEmpty {
                emptyCurrencyRow
            }

            ForEach(store.currencyRates) { rate in
                CurrencyRateRow(rateId: rate.id, initialCode: rate.code, initialRate: rate.rate)
            }
            // 自動更新改寫 store 後，用 token 讓列整批重建——
            // CurrencyRateRow 為效能刻意持有本地 @State（400ms 才提交回 store），
            // 不換 id 的話畫面會停在舊值，看起來像沒更新成功。
            .id(rateRowsRefreshToken)

            Button {
                store.currencyRates.append(CurrencyRate())
            } label: {
                Label("新增匯率", systemImage: "plus.circle")
                    .foregroundStyle(.green)
            }

            Button {
                Task { await autoUpdateRates() }
            } label: {
                HStack(spacing: 6) {
                    if isFetchingRates {
                        ProgressView().scaleEffect(0.7)
                    }
                    Label("自動更新匯率", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)
                }
            }
            .disabled(isFetchingRates || store.currencyRates.isEmpty)

            if !rateUpdateResult.isEmpty {
                Text(rateUpdateResult)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("幣別匯率")
        } footer: {
            Text("輸入幣別與對 NT$ 的比值（例：美金 = 32 元）。新增後，記帳的金額輸入欄位左側即可選擇該幣別，輸入金額時將自動換算為 NT$。「自動更新」會辨識常見幣別（美金、日圓、歐元、人民幣…）並帶入即時匯率；認不得的幣別維持手動值不變。")
        }
    }

    /// 自動更新：認得的幣別逐一抓即時匯率覆寫，認不得的不動。
    /// 結果文字停留在區塊內（不用轉瞬即逝的橫幅）——使用者需要看清楚哪些沒更新到。
    @MainActor
    private func autoUpdateRates() async {
        guard !isFetchingRates else { return }
        isFetchingRates = true
        defer { isFetchingRates = false }

        // 幣別文字 → ISO；認不得的先記下來，結果訊息要指名道姓
        var isoOf: [UUID: String] = [:]
        var unknown: [String] = []
        for r in store.currencyRates {
            let label = r.code.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            if let iso = FXRateService.isoCode(for: label) { isoOf[r.id] = iso }
            else { unknown.append(label) }
        }
        guard !isoOf.isEmpty else {
            rateUpdateResult = "沒有可辨識的幣別（支援：美金、日圓、歐元、人民幣、港幣…或直接填 USD、JPY 等代碼）"
            return
        }

        let fetched = await FXRateService.fetchRates(isoCodes: Array(Set(isoOf.values)))
        var updated = 0
        var newRates = store.currencyRates
        for idx in newRates.indices {
            guard let iso = isoOf[newRates[idx].id], let rate = fetched[iso] else { continue }
            // 保留兩位小數以上的精度（日圓 0.1982 這種小數匯率不能四捨五入成 0.2 存）
            if newRates[idx].rate != rate { newRates[idx].rate = rate; updated += 1 }
            // 美金順帶同步股票市值換算用的全域匯率，兩處口徑一致
            if iso == "USD" { UserDefaults.standard.set(rate, forKey: Stock.usdTwdRateKey) }
        }
        if updated > 0 {
            store.currencyRates = newRates
            rateRowsRefreshToken += 1
        }

        var parts: [String] = ["已更新 \(updated) 筆"]
        let failedIso = Set(isoOf.values).subtracting(fetched.keys)
        if !failedIso.isEmpty { parts.append("查詢失敗：\(failedIso.sorted().joined(separator: "、"))") }
        if !unknown.isEmpty { parts.append("無法辨識：\(unknown.joined(separator: "、"))") }
        rateUpdateResult = parts.joined(separator: "；")
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
                // 同步中不重複觸發（改在動作內守衛而非 .disabled：
                // 讓同一列右側的「重置」逃生按鈕在同步卡住時仍可點擊）
                guard !cloudSync.isSyncing else { return }
                cloudSync.syncNow()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.22), Color.blue.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.blue.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.clockwise.icloud")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(cloudSync.isAccountAvailable && cloudSync.isEnabled ? Color.blue : Color.secondary)
                    }
                    .shadow(color: Color.blue.opacity(0.15), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(cloudSync.isSyncing ? "同步中…" : "立即同步")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if cloudSync.isSyncing { ProgressView().scaleEffect(0.7).tint(.blue) }
                        }
                        Text(cloudSync.isSyncing
                             ? (cloudSync.syncProgressText ?? "正在推送資料與照片到 iCloud")
                             : "手動觸發 iCloud 資料同步")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // 同步中卡住的即時逃生口：不用等 3 分鐘看門狗，點「重置」立即解鎖
                    if cloudSync.isSyncing {
                        Button {
                            cloudSync.forceResetSyncState()
                        } label: {
                            Text("重置")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.red.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .foregroundStyle(.primary)
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
                            if verifyBusy { ProgressView().scaleEffect(0.7).tint(.cyan) }
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

            // 同步診斷：逐層測試（一般網路 → iCloud 帳號 → 資料庫讀 → 資料庫寫 → 自訂 zone），
            // 顯示每層的原始錯誤網域/代碼，一次看清楚同步到底斷在哪一層
            Button {
                runSyncDiagnostics()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.22), Color.orange.opacity(0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Circle()
                            .stroke(Color.orange.opacity(0.20), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "stethoscope")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                    .shadow(color: Color.orange.opacity(0.15), radius: 4, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("同步診斷")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if diagBusy { ProgressView().scaleEffect(0.7).tint(.orange) }
                        }
                        Text("逐層測試網路與 iCloud，找出同步斷在哪一層")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .disabled(diagBusy || !cloudSync.isEnabled)

            if let text = diagResultText {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            // 雙人共享：抽成獨立具名 View（v25.163 修復）——內聯寫法讓本 Section 的
            // SwiftUI 複合泛型型別深度爆表，執行期 decodeMangledType 遞迴展開型別
            // 中繼資料時主執行緒堆疊溢位（進設定頁即 EXC_BAD_ACCESS 於 Stack Guard）
            FamilySharingRow()

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
            Text("啟用後，記帳/理財/人生三模式的資料會透過 iCloud 在相同 Apple ID 的裝置間自動同步。資料完全儲存於你的 iCloud，LifeGood 不會收集或上傳任何資料。未登入 iCloud 帳號時無法啟用。「與家人共享資料」可邀請另一位 Apple ID（如配偶）共同編輯同一份資料，雙方即時互通。")
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
            let stampFmt = DateFormatter()
            stampFmt.dateFormat = "HH:mm"
            var lines: [String] = []
            // 帶時間戳：分辨顯示的是剛跑的結果還是舊殘留
            lines.append("[\(stampFmt.string(from: Date()))] 結構化資料：雲端 \(result.kvFound)/\(result.kvTotal) 筆"
                         + (result.latestKVDate.map { "（最後上雲 \(fmt.string(from: $0))）" } ?? ""))
            if result.photoChecked > 0 {
                lines.append("抽查最近照片：雲端 \(result.photoFound)/\(result.photoChecked) 張"
                             + (result.latestPhotoDate.map { "（最後上雲 \(fmt.string(from: $0))）" } ?? ""))
            }
            // 雲端普查：不猜 ID、直接數 zone 裡實際的記錄，切開「雲端真的空」vs「ID 對不上」
            if result.censusKV >= 0 {
                lines.append("雲端普查：資料 \(result.censusKV) 筆、照片 \(result.censusPhoto) 張")
            }
            let idMismatch = result.censusKV > 0 && result.kvFound == 0
                || (result.photoChecked > 0 && result.censusPhoto > 0 && result.photoFound == 0)
            if idMismatch, !result.censusSamples.isEmpty {
                lines.append("記錄ID樣本：\n" + result.censusSamples.joined(separator: "\n"))
                lines.append("雲端有記錄但與本機抽查的 ID 對不上，請截圖回報。")
            }
            if result.kvFound < result.kvTotal || result.photoFound < result.photoChecked {
                if result.censusKV == 0, result.censusPhoto == 0 {
                    lines.append("資料區存在但完全是空的——「推送成功」與實際不符，請截圖回報。")
                } else if !idMismatch {
                    lines.append("有項目尚未上雲：請按「立即同步」後再驗證一次。")
                }
            } else {
                lines.append("資料已確認在 iCloud 伺服器上。")
            }
            verifyResultText = lines.joined(separator: "\n")
        }
    }

    /// 同步診斷：呼叫 CloudKitManager 的逐層測試，把每層的 ✓/✗ 與原始錯誤碼顯示出來。
    /// 不受帳號狀態限制（診斷本身就是要查帳號哪裡有問題），只擋重複點擊。
    private func runSyncDiagnostics() {
        guard !diagBusy else { return }
        diagBusy = true
        diagResultText = "診斷中…（九層測試、全程最多約 3.5 分鐘；卡住的那一層會標「逾時」後自動跳下一層）"
        CloudKitManager.shared.runDiagnostics { report in
            diagBusy = false
            diagResultText = report
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

// MARK: - 雙人共享列（獨立具名 View）
//
// 必須是獨立 struct 而非內聯在 iCloudSyncSection：該 Section 子視圖眾多，內聯會讓
// SwiftUI 複合泛型型別深度爆表，執行期展開型別中繼資料（decodeMangledType 遞迴）
// 直接把主執行緒堆疊撐爆（v25.162 進設定頁即閃退的根因，見 v25.163 changelog）。

private struct FamilySharingRow: View {
    @EnvironmentObject var cloudSync: CloudSyncManager

    @State private var shareBusy = false
    @State private var sharePayload: SharePayload?
    @State private var shareErrorText: String?
    @State private var isParticipant = CloudKitManager.shared.isShareParticipant
    @State private var showLeaveConfirm = false
    @State private var leaveBusy = false

    var body: some View {
        Group {
            if isParticipant {
                participantRow
            } else {
                inviteButton
            }
            if let err = shareErrorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $sharePayload) { payload in
            CloudSharingSheet(share: payload.share, container: CloudKitManager.shared.ckContainer)
        }
        .alert("退出家人共享？", isPresented: $showLeaveConfirm) {
            Button("退出", role: .destructive) { leaveShare() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出後這台裝置改用自己的 iCloud 資料區，目前手機上的資料會保留並推送到你自己的雲端；不再與共享成員互通。")
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudKitManager.sharingStateDidChangeNotification)) { _ in
            isParticipant = CloudKitManager.shared.isShareParticipant
        }
    }

    private var participantRow: some View {
        HStack(spacing: 14) {
            sharingIconCircle("person.2.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("已加入家人共享")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("資料與共享成員即時互通（共享資料庫）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showLeaveConfirm = true
            } label: {
                Text(leaveBusy ? "退出中…" : "退出")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.red.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.22), lineWidth: 0.6))
            }
            .buttonStyle(.borderless)
            .disabled(leaveBusy)
        }
    }

    private var inviteButton: some View {
        Button {
            startSharing()
        } label: {
            HStack(spacing: 14) {
                sharingIconCircle("person.2.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("與家人共享資料")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if shareBusy { ProgressView().scaleEffect(0.7).tint(.purple) }
                    }
                    Text("邀請配偶共同編輯同一份資料，雙向即時同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .foregroundStyle(.primary)
        .disabled(shareBusy || !cloudSync.isAccountAvailable || !cloudSync.isEnabled)
    }

    private func sharingIconCircle(_ systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.purple.opacity(0.22), Color.purple.opacity(0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)
            Circle()
                .stroke(Color.purple.opacity(0.20), lineWidth: 1)
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.purple)
        }
    }

    private func startSharing() {
        guard !shareBusy else { return }
        shareBusy = true
        shareErrorText = nil
        CloudKitManager.shared.fetchOrCreateZoneShare { result in
            shareBusy = false
            switch result {
            case .success(let share):
                sharePayload = SharePayload(share: share)
            case .failure(let e):
                // 附上原始錯誤網域/代碼：共享失敗原因多樣（已存在/權限/網路），可讀碼直接定位
                let ns = e as NSError
                shareErrorText = "共享設定失敗：\(ns.domain)#\(ns.code)：\(e.localizedDescription)"
            }
        }
    }

    private func leaveShare() {
        guard !leaveBusy else { return }
        leaveBusy = true
        shareErrorText = nil
        CloudKitManager.shared.leaveShare { ok in
            leaveBusy = false
            if !ok { shareErrorText = "退出共享失敗，請稍後再試。" }
            isParticipant = CloudKitManager.shared.isShareParticipant
        }
    }
}

// MARK: - 雙人共享：CKShare 的 Identifiable 包裝與 UICloudSharingController 橋接

/// CKShare 不是 Identifiable，包一層供 .sheet(item:) 使用
struct SharePayload: Identifiable {
    let id = UUID()
    let share: CKShare
}

/// UICloudSharingController 包裝：邀請成員（訊息/AirDrop 連結）、管理參與者、停止共享
/// 全由系統介面處理；權限固定「僅受邀者・可讀寫」。
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            "LifeGood 家庭共享資料"
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            // 交給既有錯誤廣播管線：設定頁「同步錯誤」列會顯示可讀訊息
            CloudKitManager.shared.report(error, context: "共享設定")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            // 邀請已送出/權限已更新：無需額外處理，資料照常走共享 zone
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // 擁有者停止共享：自己的資料本來就在私有庫，模式不變；
            // 參與者端下次同步會收到 zoneNotFound，可自行退出共享
        }
    }
}

// MARK: - 進階設定（樹狀目錄）

/// 設定 > 進階設定：模板可調參數的樹狀目錄入口——
///   1. 圖表設定
///      1.1 趨勢曲線模板（股票／收入／變動／固定支出看板共用）
///      1.2 股票（項目卡成交量柱）
/// 之後其他模板要開放的參數，依同樣的樹狀分類往下掛新頁。
/// （注意：依 FamilySharingRow 教訓，子頁抽成獨立 struct，避免型別深度爆棧。）
struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    TrendCurveSettingsView()
                } label: {
                    advancedRow(icon: "waveform.path", color: .blue,
                                title: "趨勢曲線模板",
                                note: "股票／收入／變動／固定支出看板背景共用")
                }
                NavigationLink {
                    StockChartSettingsView()
                } label: {
                    advancedRow(icon: "chart.bar.fill", color: .orange,
                                title: "股票",
                                note: "項目卡成交量柱狀圖")
                }
            } header: {
                Text("圖表設定")
            } footer: {
                Text("之後開放的模板參數也會依分類收在這裡。")
            }
            Section {
                NavigationLink {
                    HeroCardSettingsView()
                } label: {
                    advancedRow(icon: "rectangle.fill.on.rectangle.angled.fill", color: .teal,
                                title: "英雄卡樣式",
                                note: "收入／支出／股票／儲蓄險等看板共用")
                }
                NavigationLink {
                    FlashCardSettingsView()
                } label: {
                    advancedRow(icon: "rectangle.portrait.on.rectangle.portrait.fill", color: .purple,
                                title: "閃卡樣式",
                                note: "股票／汽車／房地產詳情閃卡共用")
                }
            } header: {
                Text("卡片設定")
            }
        }
        .navigationTitle("進階設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func advancedRow(icon: String, color: Color,
                             title: String, note: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 進階設定共用滑桿列（標題 + 目前值 + bar 條）
private func advancedSliderRow(title: String, display: String,
                               value: Binding<Double>,
                               range: ClosedRange<Double>, step: Double) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(display)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        Slider(value: value, in: range, step: step)
            .tint(.blue)
    }
    .padding(.vertical, 2)
}

// MARK: 1.1 趨勢曲線模板（四張看板共用）

struct TrendCurveSettingsView: View {
    @AppStorage("hero_trend_point_count") private var pointCount: Int = 10
    @AppStorage("hero_trend_opacity") private var mainOpacity: Double = 0.30
    @AppStorage("hero_trend_line_width") private var mainLineWidth: Double = 2.0
    @AppStorage("hero_trend_blur") private var blurRadius: Double = 2.2
    @AppStorage("hero_trend_left_pos") private var leftPos: Double = 0.0
    @AppStorage("hero_trend_right_pos") private var rightPos: Double = 0.80
    @AppStorage("hero_trend_rot_x") private var rotX: Double = 5
    @AppStorage("hero_trend_rot_y") private var rotY: Double = 5
    @AppStorage("hero_trend_rot_z") private var rotZ: Double = 2
    @AppStorage("hero_trend_end_opacity") private var endOpacity: Double = 0.30
    @AppStorage("hero_trend_show_end_label") private var showEndNumber: Bool = true

    var body: some View {
        // 預覽卡固定在頂端不隨表單捲動（使用者反映調下方參數時預覽被捲出畫面外）
        VStack(spacing: 0) {
            pinnedPreview
            Form {
                paramsSection
                endPointSection
                positionSection
                rotationSection
                resetSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("趨勢曲線模板")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 置頂即時預覽（示範資料 + 真的 HeroTrendBackground，所見即所得）
    private var pinnedPreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.62, blue: 0.22),
                    Color(red: 0.86, green: 0.36, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HeroTrendBackground(points: demoPoints, stepBack: 2_592_000)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// 示範序列（12 個月、形狀固定），只給預覽卡用
    private var demoPoints: [HeroTrendPoint] {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: -11, to: Date()) ?? Date()
        let vals: [Double] = [46, 52, 49, 58, 66, 61, 72, 69, 78, 86, 90, 97]
        return vals.enumerated().map { i, v in
            HeroTrendPoint(date: cal.date(byAdding: .month, value: i, to: base) ?? base,
                           value: v * 10_000)
        }
    }

    private var paramsSection: some View {
        Section {
            advancedSliderRow(
                title: "資料點數",
                display: "\(pointCount) 點",
                value: Binding(
                    get: { Double(pointCount) },
                    set: { pointCount = Int($0.rounded()) }
                ),
                range: 4...20, step: 1
            )
            advancedSliderRow(
                title: "曲線透明度",
                display: "\(Int((mainOpacity * 100).rounded()))%",
                value: $mainOpacity,
                range: 0.10...0.80, step: 0.05
            )
            advancedSliderRow(
                title: "線條粗細",
                display: String(format: "%.1f pt", mainLineWidth),
                value: $mainLineWidth,
                range: 1.0...4.0, step: 0.5
            )
            advancedSliderRow(
                title: "景深模糊",
                display: String(format: "%.1f", blurRadius),
                value: $blurRadius,
                range: 0.0...6.0, step: 0.2
            )
        } header: {
            Text("曲線參數")
        } footer: {
            Text("套用於股票、收入、變動支出、固定支出四張看板的背景曲線，調整立即生效。回聲側線的粗細與透明度會隨主線等比例連動。")
        }
    }

    private var endPointSection: some View {
        Section {
            advancedSliderRow(
                title: "最終點透明度",
                display: "\(Int((endOpacity * 100).rounded()))%",
                value: $endOpacity,
                range: 0.10...1.00, step: 0.05
            )
            Toggle("顯示最終點數字", isOn: $showEndNumber)
                .font(.subheadline)
                .tint(.blue)
        } header: {
            Text("最終點")
        } footer: {
            Text("最終點（實心圓與數字）的透明度與曲線分開調整；關閉數字後只保留實心圓點。")
        }
    }

    private var positionSection: some View {
        Section {
            advancedSliderRow(
                title: "最左位置",
                display: "\(Int((leftPos * 100).rounded()))%",
                value: $leftPos,
                range: 0.00...0.30, step: 0.02
            )
            advancedSliderRow(
                title: "最右位置",
                display: "\(Int((rightPos * 100).rounded()))%",
                value: $rightPos,
                range: 0.50...0.95, step: 0.05
            )
        } header: {
            Text("水平位置")
        } footer: {
            Text("曲線起點與末點落在卡片寬度的百分比位置（預設 0% 與 80%——貼左緣起、末點在右邊往回 20%）。成交量柱同步套用相同位置。")
        }
    }

    private var rotationSection: some View {
        Section {
            advancedSliderRow(
                title: "X 軸旋轉",
                display: String(format: "%.0f°", rotX),
                value: $rotX,
                range: -15...15, step: 1
            )
            advancedSliderRow(
                title: "Y 軸旋轉",
                display: String(format: "%.0f°", rotY),
                value: $rotY,
                range: -15...15, step: 1
            )
            advancedSliderRow(
                title: "Z 軸旋轉",
                display: String(format: "%.0f°", rotZ),
                value: $rotZ,
                range: -15...15, step: 1
            )
        } header: {
            Text("末端數字立體旋轉")
        } footer: {
            Text("末端數值標籤的 3D 傾斜角度（預設 X 5°、Y 5°、Z 2°），營造透視感。")
        }
    }

    private var resetSection: some View {
        Section {
            Button {
                pointCount = 10
                mainOpacity = 0.30
                mainLineWidth = 2.0
                blurRadius = 2.2
                leftPos = 0.0
                rightPos = 0.80
                rotX = 5
                rotY = 5
                rotZ = 2
                endOpacity = 0.30
                showEndNumber = true
            } label: {
                Label("恢復預設值", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.blue)
        }
    }
}

// MARK: 1.2 股票（項目卡成交量柱）

struct StockChartSettingsView: View {
    @AppStorage("hero_volume_bar_opacity") private var volumeBarOpacity: Double = 0.45

    var body: some View {
        // 預覽卡固定在頂端不隨表單捲動
        VStack(spacing: 0) {
            pinnedPreview
            Form {
                paramsSection
                resetSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("股票")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 置頂即時預覽：白卡 + 橙色日線曲線與量柱，模擬實際股票項目卡
    private var pinnedPreview: some View {
        ZStack {
            Color(.systemBackground)
            HeroPriceVolumeBackground(
                prices: demoPrices,
                volumes: demoVolumes,
                tint: Color(red: 1.00, green: 0.62, blue: 0.22)
            )
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 0.75)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// 示範日線（30 天、形狀固定：緩漲＋正弦波動），只給預覽卡用
    private var demoPrices: [HeroTrendPoint] {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -29, to: Date()) ?? Date()
        return (0..<30).map { i in
            let v = 100.0 + Double(i) * 0.8 + 6.0 * sin(Double(i) / 3.5)
            return HeroTrendPoint(date: cal.date(byAdding: .day, value: i, to: base) ?? base,
                                  value: v)
        }
    }

    private var demoVolumes: [HeroTrendPoint] {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -29, to: Date()) ?? Date()
        return (0..<30).map { i in
            let v = 800.0 + 600.0 * abs(sin(Double(i) * 1.3)) + 250.0 * abs(sin(Double(i) * 0.7))
            return HeroTrendPoint(date: cal.date(byAdding: .day, value: i, to: base) ?? base,
                                  value: v)
        }
    }

    private var paramsSection: some View {
        Section {
            advancedSliderRow(
                title: "成交量柱透明度",
                display: "\(Int((volumeBarOpacity * 100).rounded()))%",
                value: $volumeBarOpacity,
                range: 0.05...0.90, step: 0.05
            )
        } header: {
            Text("成交量柱狀圖")
        } footer: {
            Text("股票項目卡底部的每日成交量柱；與曲線透明度各自獨立，調整立即生效。")
        }
    }

    private var resetSection: some View {
        Section {
            Button {
                volumeBarOpacity = 0.45
            } label: {
                Label("恢復預設值", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.blue)
        }
    }
}

// MARK: 2.2 閃卡樣式（股票／汽車／房地產詳情閃卡共用）

struct FlashCardSettingsView: View {
    @AppStorage("flash_card_corner_radius") private var cornerRadius: Double = 16
    @AppStorage("flash_card_border_scale") private var borderScale: Double = 1.0
    @AppStorage("flash_card_value_size") private var valueFontSize: Double = 52
    @AppStorage("flash_card_bokeh") private var bokehScale: Double = 1.0
    @AppStorage("flash_card_shine") private var shineIntensity: Double = 0.18
    @AppStorage("flash_card_shadow") private var shadowScale: Double = 1.0
    @AppStorage("flash_card_animation") private var appearAnimation: Bool = true
    /// 預覽用稀有度（只影響此頁預覽，不影響實際卡片——實際稀有度由資產價值決定）
    @State private var previewRarity: CardRarity = .epic

    var body: some View {
        // 預覽卡固定在頂端不隨表單捲動（使用者反映調下方參數時預覽被捲出畫面外）
        VStack(spacing: 0) {
            pinnedPreview
            Form {
                paramsSection
                resetSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("閃卡樣式")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 置頂即時預覽：示範資料跑真的 FlashCardView 模板，可切換稀有度看各級效果
    //（稀有度切換只影響預覽；實際卡片由資產價值自動分級）
    private var pinnedPreview: some View {
        VStack(spacing: 8) {
            Picker("預覽稀有度", selection: $previewRarity) {
                Text("普通").tag(CardRarity.common)
                Text("稀有").tag(CardRarity.rare)
                Text("史詩").tag(CardRarity.epic)
                Text("傳說").tag(CardRarity.legendary)
            }
            .pickerStyle(.segmented)

            FlashCardView(
                rarity: previewRarity,
                categoryLabel: "股票",
                categoryIcon: "chart.line.uptrend.xyaxis",
                title: "示範資產",
                bigNumber: "128.5",
                bigCaption: "目前市值（萬元）",
                columns: [
                    FlashCardInfoColumn("股數", "2,000"),
                    FlashCardInfoColumn("目前價", "642.50"),
                    FlashCardInfoColumn("成本價", "518.00")
                ]
            ) {
                Text("DEMO")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background((previewRarity == .legendary ? Color.white.opacity(0.18) : Color(.systemGray5)),
                                in: Capsule())
                    .foregroundStyle(previewRarity.primaryTextColor)
            } middleExtra: {
                EmptyView()
            } extraBackground: {
                EmptyView()
            }
            // 縮小以固定在頂端仍留足夠空間給下方表單；scaleEffect 不改版面
            // 尺寸，故外加 frame 高度收斂實際佔位
            .scaleEffect(0.72)
            .frame(height: 230)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var paramsSection: some View {
        Section {
            advancedSliderRow(
                title: "卡片圓角",
                display: String(format: "%.0f pt", cornerRadius),
                value: $cornerRadius,
                range: 8...28, step: 1
            )
            advancedSliderRow(
                title: "邊框粗細",
                display: String(format: "%.1f 倍", borderScale),
                value: $borderScale,
                range: 0.5...2.0, step: 0.1
            )
            advancedSliderRow(
                title: "估值字級",
                display: String(format: "%.0f pt", valueFontSize),
                value: $valueFontSize,
                range: 40...60, step: 2
            )
            advancedSliderRow(
                title: "散景亮度",
                display: String(format: "%.1f 倍", bokehScale),
                value: $bokehScale,
                range: 0.0...2.0, step: 0.1
            )
            advancedSliderRow(
                title: "玻璃光澤",
                display: "\(Int((shineIntensity * 100).rounded()))%",
                value: $shineIntensity,
                range: 0.0...0.40, step: 0.02
            )
            advancedSliderRow(
                title: "陰影強度",
                display: String(format: "%.1f 倍", shadowScale),
                value: $shadowScale,
                range: 0.0...2.0, step: 0.1
            )
            Toggle("進場動畫", isOn: $appearAnimation)
                .font(.subheadline)
                .tint(.blue)
        } header: {
            Text("卡片參數")
        } footer: {
            Text("套用於股票、汽車、房地產詳情頁的閃卡，調整立即生效。邊框粗細與陰影為各稀有度基準值的倍率。")
        }
    }

    private var resetSection: some View {
        Section {
            Button {
                cornerRadius = 16
                borderScale = 1.0
                valueFontSize = 52
                bokehScale = 1.0
                shineIntensity = 0.18
                shadowScale = 1.0
                appearAnimation = true
            } label: {
                Label("恢復預設值", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.blue)
        }
    }
}


// MARK: 2.1 英雄卡樣式（全域層；殼層／KPI／大字）

/// 全域英雄卡樣式：表單由 HeroNum 目錄自動生成——
/// 日後新增參數會自動出現在對應分區，不可能漏掉某一頁忘了加。
struct HeroCardSettingsView: View {
    @ObservedObject private var store = HeroStyleStore.shared
    /// 按住預覽 = 暫時顯示全域版（取代原本的上下半高對照卡）
    @State private var previewCard: HeroCard = .income

    var body: some View {
        VStack(spacing: 0) {
            pinnedPreview
            Form {
                ForEach(HeroNum.Bucket.allCases) { bucket in
                    Section {
                        ForEach(HeroNum.allCases.filter { $0.bucket == bucket }) { p in
                            paramRow(p)
                        }
                    } header: {
                        Text(bucket.rawValue)
                    } footer: {
                        if bucket == .kpi {
                            Text("排法決定豎分隔線的基準高度（標籤在上 28pt／數值在上 32pt／圖示在上 36pt），下方倍率只做微調。")
                        } else if bucket == .big {
                            Text("次要數值字級自動 = 大字 × 0.62，不另開滑桿。")
                        }
                    }
                }
                Section {
                    NavigationLink {
                        HeroCardOverrideListView()
                    } label: {
                        HStack {
                            Label("各卡覆寫", systemImage: "square.on.square.dashed")
                            Spacer()
                            let n = HeroCard.allCases.filter { $0 != .legacy && store.overrideCount($0) > 0 }.count
                            Text("\(n) / \(HeroCard.allCases.count - 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Section {
                    Button {
                        store.resetGlobal()
                    } label: {
                        Label("恢復預設值", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.blue)
                } footer: {
                    Text("只還原全域設定，不會清除任何卡片的覆寫。")
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("英雄卡樣式")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 置頂預覽

    private var pinnedPreview: some View {
        VStack(spacing: 8) {
            Picker("預覽卡片", selection: $previewCard) {
                Text("收入").tag(HeroCard.income)
                Text("股票").tag(HeroCard.stock)
                Text("固定支出").tag(HeroCard.fixedExpense)
            }
            .pickerStyle(.segmented)

            HeroPreviewCard(card: previewCard)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: 參數列

    @ViewBuilder
    private func paramRow(_ p: HeroNum) -> some View {
        let v = store.globalValue(p)
        if p.isEnumLike {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(p.title).font(.subheadline)
                    Spacer()
                    if store.isGlobalCustomized(p) { customizedDot }
                }
                Picker(p.title, selection: Binding(
                    get: { Int(v) },
                    set: { store.set(p, Double($0)) }
                )) {
                    if p == .kpiLayout {
                        ForEach(HeroKpiLayout.allCases) { Text($0.title).tag($0.rawValue) }
                    } else {
                        ForEach(HeroKpiChrome.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                .pickerStyle(.segmented)
                overrideNote(p)
            }
            .padding(.vertical, 2)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(p.title).font(.subheadline)
                    Spacer()
                    Text(p.display(v))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if store.isGlobalCustomized(p) { customizedDot }
                }
                Slider(value: Binding(get: { v }, set: { store.set(p, $0) }),
                       in: p.range, step: p.step)
                    .tint(.blue)
                overrideNote(p)
            }
            .padding(.vertical, 2)
        }
    }

    private var customizedDot: some View {
        Circle().fill(.blue).frame(width: 6, height: 6)
    }

    /// 有卡片覆寫此項時，給行動而不只給警告
    @ViewBuilder
    private func overrideNote(_ p: HeroNum) -> some View {
        let cards = store.cardsOverriding(p)
        if !cards.isEmpty {
            HStack(spacing: 6) {
                Text("\(cards.count) 張卡自訂此項")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("一併套用") { store.clearOverridesEverywhere(p) }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
    }
}

// MARK: 2.2 各卡覆寫清單

struct HeroCardOverrideListView: View {
    @ObservedObject private var store = HeroStyleStore.shared
    @State private var showOnlyCustomized = false

    private var cards: [HeroCard] {
        HeroCard.allCases.filter { $0 != .legacy }
    }

    var body: some View {
        Form {
            Section {
                Picker("篩選", selection: $showOnlyCustomized) {
                    Text("全部（\(cards.count)）").tag(false)
                    Text("已自訂（\(cards.filter { store.overrideCount($0) > 0 }.count)）").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            }
            ForEach(HeroCard.Family.allCases) { family in
                let list = cards.filter {
                    $0.family == family && (!showOnlyCustomized || store.overrideCount($0) > 0)
                }
                if !list.isEmpty {
                    Section(family.rawValue) {
                        ForEach(list) { card in
                            NavigationLink {
                                HeroCardOverrideView(card: card)
                            } label: {
                                cardRow(card)
                            }
                        }
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    store.resetAllCards()
                } label: {
                    Label("全部恢復跟隨全域", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("各卡覆寫")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cardRow(_ card: HeroCard) -> some View {
        let n = store.overrideCount(card)
        return HStack(spacing: 10) {
            // 出廠漸層小色票：一眼認出是哪張卡
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: card.factoryGradient,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title).font(.subheadline)
                // 殼層還沒遷移的卡：先講清楚調了不會動，免得被當成壞掉
                if !card.isWired {
                    Text("殼層尚未接上，調整暫時不會生效")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if n > 0 {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text("自訂 \(n) 項")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("跟隨全域")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 2.3 單卡覆寫

/// 單一參數化 struct，絕不為每張卡各寫一份（FamilySharingRow 型別深度爆棧的教訓）
struct HeroCardOverrideView: View {
    let card: HeroCard
    @ObservedObject private var store = HeroStyleStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HeroPreviewCard(card: card)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            Form {
                Section {
                    let n = store.overrideCount(card)
                    Text(n > 0 ? "已自訂 \(n) 項 · 其餘跟隨全域" : "完全跟隨全域")
                        .font(.caption)
                        .foregroundStyle(n > 0 ? .orange : .secondary)
                    if !card.isWired {
                        Label("這張卡的殼層還在手刻背景，尚未接上樣式系統。這裡的設定會存起來，等它遷移完成後自動生效，但現在調整畫面不會有反應。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if card == .settings {
                        Label("這張卡的漸層平常依訂閱狀態自動切換（付費綠／未付費紫）。一旦在下方指定了漸層顏色，就會固定用你指定的顏色、不再隨狀態變化；想恢復自動切換，把該項切回「跟隨全域」即可。",
                              systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("顏色") {
                    ForEach(HeroTint.allCases) { t in
                        colorRow(t)
                    }
                }
                Section("可覆寫參數") {
                    ForEach(HeroNum.allCases.filter { $0.supportsPerCard }) { p in
                        overridableRow(p)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        store.resetCard(card)
                    } label: {
                        Label("此卡恢復跟隨全域", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.overrideCount(card) == 0)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(card.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // 三態列：跟隨（灰、無控制項）→ 打開 Toggle 後才長出控制項（橙）
    @ViewBuilder
    private func overridableRow(_ p: HeroNum) -> some View {
        let overridden = store.isOverridden(p, card)
        let resolved = store.value(p, card)
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { overridden },
                // 打開時 seed 成「當下的全域解析值」而非出廠值——一打開就跳版最勸退
                set: { on in
                    if on { store.set(p, store.globalValue(p), card: card) }
                    else { store.clear(p, card: card) }
                }
            )) {
                HStack {
                    Text(p.title).font(.subheadline)
                    Spacer()
                    Text(overridden ? p.display(resolved) : "跟隨全域 · \(p.display(store.globalValue(p)))")
                        .font(.caption)
                        .foregroundStyle(overridden ? .orange : .secondary)
                        .monospacedDigit()
                }
            }
            .tint(.orange)

            if overridden {
                if p.isEnumLike {
                    Picker(p.title, selection: Binding(
                        get: { Int(resolved) },
                        set: { store.set(p, Double($0), card: card) }
                    )) {
                        if p == .kpiLayout {
                            ForEach(HeroKpiLayout.allCases) { Text($0.title).tag($0.rawValue) }
                        } else {
                            ForEach(HeroKpiChrome.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Slider(value: Binding(
                        get: { resolved },
                        set: { store.set(p, $0, card: card) }
                    ), in: p.range, step: p.step)
                        .tint(.orange)
                }
                Button("回到全域") { store.clear(p, card: card) }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func colorRow(_ t: HeroTint) -> some View {
        let overridden = store.isOverridden(t, card)
        let s = store.style(for: card)
        let current: Color = {
            switch t {
            case .gradA:  return s.gradient[0]
            case .gradB:  return s.gradient[1]
            case .bokeh:  return s.bokehTint
            case .shadow: return s.shadowTint
            }
        }()
        HStack {
            ColorPicker(t.title, selection: Binding(
                get: { current },
                set: { store.setColor(t, $0, card: card) }
            ), supportsOpacity: false)
            if overridden {
                Button {
                    store.clear(t, card: card)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: 預覽卡（跑真殼層＋真 KPI＋真趨勢曲線）

/// 設定頁的即時預覽：用真的 heroCardShell / HeroKpiCell 跑，
/// 示範字串刻意用「該卡可能出現的最長值」，才看得出何時開始被 minimumScaleFactor 縮掉。
struct HeroPreviewCard: View {
    let card: HeroCard
    @ObservedObject private var store = HeroStyleStore.shared

    var body: some View {
        let s = store.style(for: card)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                    Text("NT$1,284.6億")
                        .font(.system(size: s.bigValueSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer()
                Text("26 筆")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            HStack(spacing: 0) {
                HeroKpiCell(label: "年度預估", value: "NT$154萬", icon: "calendar")
                HeroKpiDivider()
                HeroKpiCell(label: "日均", value: "NT$4,265", icon: "sun.max.fill")
                HeroKpiDivider()
                HeroKpiCell(label: "月均", value: "NT$12.8萬", icon: "chart.bar.fill")
            }
            .padding(.vertical, s.kpiChrome == .bare ? 4 : 10)
            .background(s.kpiChrome == .bare ? Color.clear : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if s.kpiChrome == .plateStroked {
                    RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18), lineWidth: 0.75)
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .heroCardShell(card: card) {
            HeroTrendBackground(points: Self.demoPoints, stepBack: 2_592_000)
        }
    }

    /// 示範序列（12 個月、形狀固定）
    private static var demoPoints: [HeroTrendPoint] {
        let cal = Calendar.current
        let base = cal.date(byAdding: .month, value: -11, to: Date()) ?? Date()
        let vals: [Double] = [52, 61, 55, 68, 74, 70, 82, 78, 88, 95, 102, 128]
        return vals.enumerated().map { i, v in
            HeroTrendPoint(date: cal.date(byAdding: .month, value: i, to: base) ?? base,
                           value: v * 1_000)
        }
    }
}
