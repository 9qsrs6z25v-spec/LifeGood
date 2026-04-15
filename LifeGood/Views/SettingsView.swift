import SwiftUI
import UniformTypeIdentifiers

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

    var id: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var url: URL {
        switch self {
        case .json(let url), .csv(let url): return url
        }
    }
}

// MARK: - 設定頁面

struct SettingsView: View {
    @EnvironmentObject var store: ExpenseStore
    @EnvironmentObject var financeStore: FinanceStore
    @AppStorage("appMode") private var appMode: String = AppMode.expense.rawValue

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
    @State private var importResultMessage = ""
    @State private var showImportResult = false

    // 清除狀態
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                modeSwitchSection
                dataManagementSection
                dataStatsSection
                dangerZoneSection
                aboutSection
            }
            .navigationTitle("設定")
            // 匯出分享
            .sheet(item: $activeShareItem) { item in
                ShareSheet(items: [item.url])
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
                allowedContentTypes: [.json],
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
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作無法復原，所有支出紀錄將被永久刪除。建議先匯出備份再進行清除。")
            }
        }
    }

    // MARK: - 模式切換

    private var modeSwitchSection: some View {
        Section {
            Picker("功能模式", selection: $appMode) {
                ForEach(AppMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("功能切換")
        } footer: {
            Text(currentMode == .expense
                 ? "目前為記帳模式：管理每日變動支出與固定開支。"
                 : "目前為理財模式：管理儲蓄險、股票與房地產資產。")
        }
    }

    // MARK: - 資料管理

    private var dataManagementSection: some View {
        Section {
            // 匯出 JSON
            Button {
                exportJSON()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("匯出 JSON")
                        Text("完整資料備份，可重新匯入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.green)
                }
            }
            .foregroundStyle(.primary)

            // 匯出 CSV
            Button {
                exportCSV()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("匯出 CSV")
                        Text("可用 Excel 或 Numbers 開啟")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "tablecells")
                        .foregroundStyle(.green)
                }
            }
            .foregroundStyle(.primary)

            // 匯入
            Button {
                showImporter = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("匯入資料")
                        Text("從 JSON 備份檔案匯入")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.blue)
                }
            }
            .foregroundStyle(.primary)
        } header: {
            Text("資料管理")
        } footer: {
            Text("匯出的 JSON 檔案可用於備份或轉移至其他裝置。CSV 檔案適合在試算表軟體中檢視分析。")
        }
    }

    // MARK: - 資料統計

    private var dataStatsSection: some View {
        Section("資料統計") {
            HStack {
                Label("總筆數", systemImage: "number")
                Spacer()
                Text("\(store.expenses.count) 筆")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("變動支出", systemImage: "arrow.up.arrow.down.circle")
                Spacer()
                Text("\(store.variableExpenses.count) 筆")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("固定支出", systemImage: "pin.circle")
                Spacer()
                Text("\(store.fixedExpenses.count) 筆")
                    .foregroundStyle(.secondary)
            }

            if let earliest = store.expenses.map(\.date).min(),
               let latest = store.expenses.map(\.date).max() {
                HStack {
                    Label("資料區間", systemImage: "calendar")
                    Spacer()
                    Text("\(formatDate(earliest)) ~ \(formatDate(latest))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 危險區域

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清除所有資料", systemImage: "trash")
            }
            .disabled(store.expenses.isEmpty)
        } header: {
            Text("危險操作")
        } footer: {
            Text("清除後無法復原，請先匯出備份。")
        }
    }

    // MARK: - 關於

    private var aboutSection: some View {
        Section("關於") {
            HStack {
                Label("版本", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Build", systemImage: "hammer")
                Spacer()
                Text(appBuild)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("最低系統需求", systemImage: "iphone")
                Spacer()
                Text("iOS 17.0")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 匯出

    private func exportJSON() {
        let data = store.exportJSON()
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
        let csv = store.exportCSV()
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
                let data = try Data(contentsOf: url)
                pendingImportData = data
                showImportModeAlert = true
            } catch {
                importResultMessage = "讀取檔案失敗：\(error.localizedDescription)"
                showImportResult = true
            }
        case .failure(let error):
            importResultMessage = "選取檔案失敗：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    private func performImport(mode: ExpenseStore.ImportMode) {
        guard let data = pendingImportData else { return }
        let count = store.importJSON(data: data, mode: mode)
        switch mode {
        case .merge:
            importResultMessage = "成功匯入 \(count) 筆新紀錄"
        case .replace:
            importResultMessage = "已取代為匯入的 \(count) 筆紀錄"
        }
        pendingImportData = nil
        showImportResult = true
    }

    // MARK: - Helpers

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
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
}
