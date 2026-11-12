import SwiftUI
import UserNotifications

// MARK: - [v25.625] 水電 v6（util6）：設定 › 「會議提醒」那一塊的兩顆開關（radar/build/util6/brief.md）
//
// • 「水電用得比較多時通知我」（UtilityHighNotice.enabledKey，沒設過＝開）
// • 「通知裡不要出現房子名稱」（UtilityHighNotice.hideNameKey，沒設過＝關；上面那顆關著時灰掉）
// 都只存這台（@AppStorage＝UserDefaults.standard），不是同步鍵、不進備份。
// 一動就交給 UtilityHighNoticeCenter（關掉＝待發的全部拿掉；換名字設定＝待發的那幾則重寫內文）。
// 通知權限只讀狀態、不在這裡跳權限要求（照既有的入口：行事曆、財富提醒第一次排的時候問）。
// SettingsView 很大、型別檢查敏感：那邊的 Group 裡只多一個名字 UtilityNoticeSettingsRows()。

struct UtilityNoticeSettingsRows: View {
    @AppStorage(UtilityHighNotice.enabledKey) private var enabled = true
    @AppStorage(UtilityHighNotice.hideNameKey) private var hideName = false
    /// 通知權限沒開時的那一行灰字（開著＝nil）；只讀狀態
    @State private var permissionNote: String? = nil
    /// 從 iOS 設定改完通知權限回來時重讀一次（只改上面那個 @State，不寫 store、不排通知）
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        enabledToggle
        hideNameToggle
        permissionRow
    }

    /// 兩顆下面的權限灰字：這支手機沒允許通知時就出現（brief §4.8／§5.6：權限被拒 → 下面一行灰字）
    @ViewBuilder
    private var permissionRow: some View {
        if let note = permissionNote {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var enabledToggle: some View {
        Toggle(isOn: $enabled) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.enabledTitle)
                    Text(Self.enabledHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: enabled) { _, _ in
            UtilityHighNoticeCenter.shared.enabledChanged()
        }
        .task {
            await readPermission()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await readPermission() }
        }
    }

    private var hideNameToggle: some View {
        Toggle(isOn: $hideName) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.hideNameTitle)
                    Text(Self.hideNameHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(.orange)
            }
        }
        .disabled(!enabled)
        .onChange(of: hideName) { _, _ in
            UtilityHighNoticeCenter.shared.hideNameChanged()
        }
    }

    /// 只讀通知權限的狀態（不要求權限、不寫任何 store）
    private func readPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionNote = Self.note(settings.authorizationStatus)
    }

    static func note(_ s: UNAuthorizationStatus) -> String? {
        switch s {
        case .authorized, .provisional, .ephemeral:
            return nil
        case .denied:
            return deniedNote
        case .notDetermined:
            return undecidedNote
        @unknown default:
            return nil
        }
    }

    // 字一律單一字串常數，不要在 Text(...) 裡用 + 串接
    static let enabledTitle = "水電用得比較多時通知我"
    static let enabledHint =
        "在房子的水電瓦斯存了最新的一期、出現「這期用得比較多」的橘字時，隔天晚上 8 點通知一次；同一間同一種 30 天最多一則。只在這支手機，不同步。通知不寫金額、度數、電號"
    static let hideNameTitle = "通知裡不要出現房子名稱"
    static let hideNameHint = "開了改寫成「有一間房子這期用電比去年同期多，打開看看」"
    static let deniedNote = "這支手機關掉了 LifeGood 的通知，水電的通知收不到；要收到請到 iOS「設定 › 通知 › LifeGood」打開"
    static let undecidedNote = "還沒允許過 LifeGood 發通知；存水電時不會跳出來問，等行事曆或財富提醒問你時允許，就收得到"
}
