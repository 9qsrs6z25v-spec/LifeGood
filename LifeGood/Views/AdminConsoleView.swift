import SwiftUI

/// 隱藏管理控制台（關於頁連點版本卡 20 下開啟，需輸入 PIN）。
/// 可：查看不重複 iCloud 使用者人數、切換「全功能免費」總開關、設定對外人數顯示、改 PIN。
struct AdminConsoleView: View {
    @ObservedObject private var admin = RemoteAdminManager.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var enteredPIN = ""
    @State private var unlocked = false
    @State private var pinError = false

    // 鏡像狀態（驅動 Toggle / TextField，再寫回遠端）
    @State private var allFreeMirror = false
    @State private var showPublicMirror = false
    @State private var thresholdText = ""
    @State private var newPIN = ""

    var body: some View {
        NavigationStack {
            Group {
                if unlocked { console } else { pinGate }
            }
            .navigationTitle("管理控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("關閉") { dismiss() } }
            }
        }
        .onAppear { syncMirrors() }
    }

    private func syncMirrors() {
        allFreeMirror = admin.allFree
        showPublicMirror = admin.showCountPublicly
        thresholdText = "\(admin.countThreshold)"
    }

    // MARK: - PIN 閘門

    private var pinGate: some View {
        Form {
            Section {
                SecureField("輸入 PIN", text: $enteredPIN)
                    .keyboardType(.numberPad)
                Button("解鎖") {
                    if enteredPIN == admin.adminPIN {
                        unlocked = true; pinError = false; syncMirrors()
                    } else {
                        pinError = true
                    }
                }
            } footer: {
                if pinError { Text("PIN 錯誤").foregroundStyle(.red) }
            }
        }
    }

    // MARK: - 控制台

    private var console: some View {
        Form {
            // 人數
            Section("使用者人數（不重複 iCloud）") {
                HStack {
                    Image(systemName: "person.3.fill").foregroundStyle(.blue)
                    Text("目前人數")
                    Spacer()
                    Text("\(admin.userCount)").bold().monospacedDigit()
                }
                Button {
                    admin.refresh()
                } label: {
                    Label("重新整理人數 / 設定", systemImage: "arrow.clockwise")
                }
            }

            // 訂閱總開關
            Section {
                Toggle("全功能免費（所有使用者）", isOn: $allFreeMirror)
                    .onChange(of: allFreeMirror) { _, newValue in
                        // 只有使用者實際撥動時才寫遠端（避免 onAppear 同步鏡像時誤觸）
                        if newValue != admin.allFree { admin.adminSetAllFree(newValue) }
                    }
                HStack {
                    Text("本機目前狀態")
                    Spacer()
                    Text(subscription.isPremium ? "已解鎖" : "已上鎖")
                        .foregroundStyle(subscription.isPremium ? .green : .red)
                }
                Toggle("本機開發者強制解鎖", isOn: $subscription.devOverride)
            } header: {
                Text("訂閱")
            } footer: {
                Text("「全功能免費」會即時影響所有使用者（寫入 iCloud 公開設定）。關閉後，免費期間就在用的早鳥使用者仍永久保留解鎖。")
            }

            // 對外人數顯示
            Section {
                Toggle("對外顯示人數", isOn: $showPublicMirror)
                    .onChange(of: showPublicMirror) { _, newValue in
                        if newValue != admin.showCountPublicly { applyPublicDisplay() }
                    }
                HStack {
                    Text("顯示門檻")
                    Spacer()
                    TextField("1000", text: $thresholdText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .onSubmit { applyPublicDisplay() }
                }
                Button("套用門檻") { applyPublicDisplay() }
            } header: {
                Text("對外顯示")
            } footer: {
                Text("開啟且人數達門檻後，「關於」頁會顯示「已有 N 位使用者」。目前 \(admin.shouldShowPublicCount ? "會" : "不會")對外顯示。")
            }

            // PIN
            Section("PIN") {
                SecureField("新的 PIN", text: $newPIN).keyboardType(.numberPad)
                Button("更新 PIN") {
                    admin.setAdminPIN(newPIN)
                    newPIN = ""
                }
                .disabled(newPIN.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let err = admin.lastError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private func applyPublicDisplay() {
        let threshold = Int(thresholdText.filter { $0.isNumber }) ?? admin.countThreshold
        thresholdText = "\(threshold)"
        admin.adminSetPublicDisplay(enabled: showPublicMirror, threshold: threshold)
    }
}
