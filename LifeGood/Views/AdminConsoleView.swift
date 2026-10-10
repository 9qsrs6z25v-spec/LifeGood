import SwiftUI

// MARK: - 美化紀錄（AdminConsoleView）
// [2026-06 v1] 本次美化方向：
//   1. pinGate 鎖定頁：插入 56pt 鎖頭漸層圓（紫→靛，含 shadow + stroke 0.75pt）作視覺錨點，
//      說明文字雙行分層（標題 .headline / 副說明 .caption），
//      PIN 輸入錯誤從純 .red Text 升級為 Capsule 錯誤徽章（紅底半透明 + stroke 0.75pt），
//      對齊 SettingsView / PaywallView 頁頭視覺規格。
//   2. 控制台使用者人數列：升級為 36pt 藍色漸層圓圖示 + Circle().stroke(0.75pt) 邊框 + shadow，
//      對齊 SettingsView settingsActionRow 圖示圓規格。
//   3. 訂閱狀態值（已解鎖/已上鎖）：從純色 .foregroundStyle 升級為彩色 Capsule 狀態徽章，
//      綠底 / 紅底（0.12~0.15 透明度）+ 對應色 stroke 0.75pt，
//      對齊 OverviewView / StockView 狀態 Capsule 設計語言。
//   4. 解鎖過渡動畫：解鎖按鈕改以 withAnimation(.spring(response:0.5, dampingFraction:0.78))
//      切換 unlocked 狀態，console Form 加 .onAppear fade-in（opacity + Y 12pt 偏移），
//      讓 PIN 閘門→控制台的切換更流暢，對齊全 App spring 進場動畫規格。
//   5. ChangelogListView 版本標頭：版本號從純 .headline Text 升級為
//      LinearGradient Capsule 徽章（藍→靛 + .white 文字），
//      日期改 Capsule 徽章（.tertiarySystemFill 底色 + separator stroke 0.6pt），
//      build 號維持 .caption 輔助文字；更新條目 bullet 圓從 5pt 升為 7pt 並加藍色漸層填色，
//      對齊 StockDetailView sectionHeader / FamilyMembersResumeView 日期 Capsule 規格。
// [2026-07 v2] 補齊「載入狀態」缺口：
//   6. RemoteAdminManager 早已提供 @Published isBusy（寫入 CloudKit AppConfig 期間會切
//      true/false），但畫面先前完全沒有讀取，切換「全功能免費」/「對外顯示人數」門檻時，
//      使用者在網路寫入期間看不到任何進行中提示，也可能連續多次觸發造成重疊寫入。
//      新增條件式 Section（與既有 lastError 錯誤區塊同款式）：isBusy 時於「使用者人數」
//      與「訂閱」之間顯示 ProgressView + 「正在與 iCloud 同步設定…」提示列，寫入完成後自動
//      消失；同時把「全功能免費」/「對外顯示人數」Toggle 與「套用門檻」按鈕在 isBusy 期間
//      disabled，避免重複觸發。純 UI 呈現既有狀態旗標，未新增或變動任何遠端讀寫邏輯。
// [2026-07 v3] 補齊「視覺一致性」缺口：console 內 5 個 Section 先前仍是預設純文字
//   header（Section("...")），未套用 v1 就已在 pinGate/使用者人數列建立的漸層規格；
//   全 App 多數頁面（SubordinateRosterView.RosterCellDetailSheet、OrganizationView 等）
//   Section 標題已統一改為「4pt Capsule 漸層色條 + 圖示 + .subheadline.semibold」，
//   此頁落後於均值。新增 sectionHeader(_:icon:color:) 輔助函式並套用到全部 5 個 Section
//   （使用者人數＝藍／訂閱＝綠／對外顯示＝紫／版本更新紀錄＝靛／PIN＝橘），純標題視覺
//   升級，Section 內容、Toggle、Button 行為完全未變動。
// [2026-07 v4] 補齊兩處細節：
//   1. 「目前人數」數字補上 .lineLimit(1) + .minimumScaleFactor(0.6)：本頁是全 App
//      唯一顯示大型數字卻沒有防截斷保護的地方（其餘頁面金額類數字皆已透過 ntdWanString
//      或個別補上 minimumScaleFactor），使用者數成長到 5 位數以上時可自動縮字，不會被裁切。
//   2. 「版本更新紀錄」Section 內「最新：v...」摘要行，原本是裸 .caption Text，
//      與同一 Section 底下 NavigationLink 進去的 ChangelogListView.changelogHeader
//      版本徽章（藍→靛漸層 Capsule）風格脫節；改為迷你版同款漸層 Capsule 徽章 +
//      build 輔助文字，讓摘要行與詳情頁版本徽章視覺語言一致。
//   純視覺層調整，人數讀取、版本紀錄資料來源等既有商業邏輯完全未變動。
// [2026-08 v5] 補齊 isBusy 同步提示列 ProgressView 主題色：
//   1. 「正在與 iCloud 同步設定…」列的 ProgressView() 從 v2 建立以來就是系統預設灰色
//      轉輪，經全 App 17 處 ProgressView() 呼叫點逐一核對，是唯一沒有 .tint() 的一處；
//      其餘全部都跟隨所在區塊主題色（例如 SettingsView.actionRow 依傳入 color 上色、
//      RealEstateDetailView CutePhotoViewer 用 draft.kind.accent）。本提示列緊接在
//      「使用者人數」Section 之後、寫入的正是該 Section 觸發的門檻設定，補上
//      .tint(.blue) 沿用該 Section 的藍色主題（sectionHeader 第 215 行同色），讓載入中
//      轉輪與上方剛互動的區塊同色系，不再是唯一一顆脫色的灰色轉輪。
//   純視覺層調整，admin.isBusy 讀取與 CloudKit AppConfig 寫入等既有商業邏輯完全未變動。
//   （下次美化本檔案時，可轉往其他仍留有待辦的畫面）
// ─────────────────────────────────────────────

/// 隱藏管理控制台（關於頁連點版本卡 20 下開啟，需輸入 PIN）。
/// 可：查看不重複 iCloud 使用者人數、切換「全功能免費」總開關、設定對外人數顯示、改 PIN。
struct AdminConsoleView: View {
    @StateObject private var admin = RemoteAdminManager.shared
    @StateObject private var subscription = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var enteredPIN = ""
    @State private var unlocked = false
    @State private var pinError = false

    // 鏡像狀態（驅動 Toggle / TextField，再寫回遠端）
    @State private var allFreeMirror = false
    @State private var showPublicMirror = false
    @State private var thresholdText = ""
    @State private var newPIN = ""

    // 控制台進場動畫
    @State private var consoleAppeared = false

    var body: some View {
        NavigationStack {
            Group {
                if unlocked {
                    console
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                } else {
                    pinGate
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: unlocked)
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
            // 視覺錨點：56pt 鎖頭漸層圓 + 標題 / 副說明文字
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: .purple.opacity(0.28), radius: 10, y: 4)
                        Circle()
                            .stroke(Color.purple.opacity(0.20), lineWidth: 0.75)
                            .frame(width: 56, height: 56)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 8)

                    Text("輸入管理員 PIN")
                        .font(.headline)

                    Text("僅限授權管理員使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.bottom, 4)
            }

            Section {
                SecureField("輸入 PIN", text: $enteredPIN)
                    .keyboardType(.numberPad)
                Button("解鎖") {
                    if enteredPIN == admin.adminPIN {
                        pinError = false
                        syncMirrors()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                            unlocked = true
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            pinError = true
                        }
                    }
                }
            } footer: {
                if pinError {
                    // 升級：Capsule 錯誤徽章（半透明紅底 + stroke）
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                        Text("PIN 錯誤，請重新輸入")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.28), lineWidth: 0.75))
                    .foregroundStyle(.red)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - 控制台

    private var console: some View {
        Form {
            // 人數
            Section {
                HStack(spacing: 12) {
                    // 36pt 藍色漸層圓圖示（對齊 SettingsView settingsActionRow）
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .shadow(color: .blue.opacity(0.22), radius: 6, y: 2)
                        Circle()
                            .stroke(Color.blue.opacity(0.18), lineWidth: 0.75)
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("目前人數")
                    Spacer()
                    Text("\(admin.userCount)")
                        .bold()
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                Button {
                    admin.refresh()
                } label: {
                    Label("重新整理人數 / 設定", systemImage: "arrow.clockwise")
                }
            } header: {
                sectionHeader("使用者人數（不重複 iCloud）", icon: "person.3.fill", color: .blue)
            }

            // [v2] 載入狀態：isBusy 時顯示同步提示（寫入 CloudKit AppConfig 期間）
            if admin.isBusy {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.blue)
                        Text("正在與 iCloud 同步設定…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }

            // 訂閱總開關
            Section {
                Toggle("全功能免費（所有使用者）", isOn: $allFreeMirror)
                    .disabled(admin.isBusy)
                    .onChange(of: allFreeMirror) { _, newValue in
                        // 只有使用者實際撥動時才寫遠端（避免 onAppear 同步鏡像時誤觸）
                        if newValue != admin.allFree {
                            admin.adminSetAllFree(newValue) { ok in
                                // 寫入失敗時 admin.allFree 未變，把鏡像撥回真實狀態，
                                // 避免 Toggle 一直顯示使用者以為已生效的錯誤狀態
                                if !ok { allFreeMirror = admin.allFree }
                            }
                        }
                    }
                HStack {
                    Text("本機目前狀態")
                    Spacer()
                    // 升級：彩色 Capsule 狀態徽章（綠/紅）
                    let isPremium = subscription.isPremium
                    Text(isPremium ? "已解鎖" : "已上鎖")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(isPremium ? Color.green.opacity(0.15) : Color.red.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(
                                isPremium ? Color.green.opacity(0.30) : Color.red.opacity(0.25),
                                lineWidth: 0.75
                            )
                        )
                        .foregroundStyle(isPremium ? .green : .red)
                }
                Toggle("本機開發者強制解鎖", isOn: $subscription.devOverride)
            } header: {
                sectionHeader("訂閱", icon: "crown.fill", color: .green)
            } footer: {
                Text("「全功能免費」會即時影響所有使用者（寫入 iCloud 公開設定）。關閉後，免費期間就在用的早鳥使用者仍永久保留解鎖。")
            }

            // 對外人數顯示
            Section {
                Toggle("對外顯示人數", isOn: $showPublicMirror)
                    .disabled(admin.isBusy)
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
                    .disabled(admin.isBusy)
            } header: {
                sectionHeader("對外顯示", icon: "eye.fill", color: .purple)
            } footer: {
                Text("開啟且人數達門檻後，「關於」頁會顯示「已有 N 位使用者」。目前 \(admin.shouldShowPublicCount ? "會" : "不會")對外顯示。")
            }

            // 版本更新紀錄（內建，僅管理者檢視）
            Section {
                NavigationLink {
                    ChangelogListView()
                } label: {
                    Label("檢視更新紀錄（\(Changelog.entries.count) 版）", systemImage: "doc.text.clock")
                }
                if let latest = Changelog.entries.first {
                    // [v4] 迷你版本徽章，對齊 ChangelogListView.changelogHeader 藍→靛漸層規格
                    HStack(spacing: 6) {
                        Text("最新")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("v\(latest.version)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.indigo],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                            )
                            .foregroundStyle(.white)
                        Text("build \(latest.build)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                sectionHeader("版本更新紀錄", icon: "doc.text.clock", color: .indigo)
            }

            // PIN
            Section {
                SecureField("新的 PIN", text: $newPIN).keyboardType(.numberPad)
                Button("更新 PIN") {
                    admin.setAdminPIN(newPIN)
                    newPIN = ""
                }
                .disabled(newPIN.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                sectionHeader("PIN", icon: "key.fill", color: .orange)
            }

            if let err = admin.lastError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }
        }
        // 控制台整體淡入 + 上移進場動畫（解鎖後觸發）
        .opacity(consoleAppeared ? 1 : 0)
        .offset(y: consoleAppeared ? 0 : 12)
        // [v2] 同步提示 Section 出現/消失加淡入淡出，避免 isBusy 切換時列表跳動
        .animation(.easeInOut(duration: 0.25), value: admin.isBusy)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.08)) {
                consoleAppeared = true
            }
        }
        .onDisappear { consoleAppeared = false }
    }

    // Section 標題輔助（4pt Capsule 漸層色條 + 圖示 + .subheadline.semibold，對齊全 App sectionHeader 規格）
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 16)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }

    private func applyPublicDisplay() {
        let threshold = Int(thresholdText.filter { $0.isNumber }) ?? admin.countThreshold
        thresholdText = "\(threshold)"
        admin.adminSetPublicDisplay(enabled: showPublicMirror, threshold: threshold) { ok in
            // 寫入失敗時 admin.showCountPublicly/countThreshold 未變，把鏡像撥回真實狀態
            if !ok {
                showPublicMirror = admin.showCountPublicly
                thresholdText = "\(admin.countThreshold)"
            }
        }
    }
}

// MARK: - 版本更新紀錄清單（內建、新到舊）

struct ChangelogListView: View {
    var body: some View {
        List {
            ForEach(Changelog.entries) { entry in
                Section {
                    ForEach(Array(entry.notes.enumerated()), id: \.offset) { _, note in
                        changelogRow(note)
                    }
                } header: {
                    changelogHeader(entry)
                }
            }
        }
        .navigationTitle("版本更新紀錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 拆分為獨立子視圖，避免單一表達式過於複雜導致型別檢查逾時
    private func changelogRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 7pt 藍色漸層 bullet 點
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo.opacity(0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            Text(note).font(.subheadline)
        }
    }

    private func changelogHeader(_ entry: ChangelogEntry) -> some View {
        HStack(spacing: 6) {
            // 版本號 LinearGradient Capsule 徽章（藍→靛）
            Text("v\(entry.version)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundStyle(.white)

            Text("build \(entry.build)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // 日期 Capsule 徽章（tertiarySystemFill + stroke 0.6pt）
            Text(entry.date)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .overlay(Capsule().stroke(Color(.separator).opacity(0.40), lineWidth: 0.6))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
}
