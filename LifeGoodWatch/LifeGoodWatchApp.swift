import Foundation
import SwiftUI

// MARK: - 手錶 App 進入點（手錶 v0，v25.573）
//
// 只屬於「LifeGoodWatch」target（com.lifegood.app.watchkitapp，watchOS 11.0，依附 iPhone 的 LifeGood）。
// v0 是空殼：只驗專案設定、簽章、嵌入、安裝（scratchpad/watch/judge.md §7.7、§8 v0）。
// 一頁：☀︎（SF Symbol sun.max.fill）＋「LifeGood」「手錶版準備中」＋版號（Bundle.main 讀，見 WatchBuildInfo）。
// 畫面上不放 App 圖示：AppIcon 素材不能當成一般圖片在畫面上讀出來（critic 🟠8）。
// v1 換成 RootView（垂直翻頁）＋WKApplicationDelegateAdaptor。
//
// 寫法守則（judge §7.8）：手錶 target 只准 import SwiftUI、WidgetKit、WatchKit、WatchConnectivity、Foundation；
// 不准 UIKit、ActivityKit、CoreImage、Speech、AlarmKit、CloudKit。v0 不編任何共用檔。

@main
struct LifeGoodWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchComingSoonView()
        }
    }
}

/// v0 唯一的一頁：☀︎＋「LifeGood」「手錶版準備中」＋「版本 25.573（1326）」。
/// 字全部用系統字級，41mm／40mm 也放得下；ScrollView 讓放大字級時捲得到。不放 App 圖示（AppIcon 讀不出來）。
struct WatchComingSoonView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                sunSymbol
                Text("LifeGood")
                    .font(.headline)
                Text("手錶版準備中")
                    .font(.body)
                versionText
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    /// ☀︎：SF Symbol（watchOS 6 起就有），不是 App 圖示
    private var sunSymbol: some View {
        Image(systemName: "sun.max.fill")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Color.yellow)
            .accessibilityHidden(true)
    }

    /// 版號那一行；兩個都讀不到就不畫
    @ViewBuilder
    private var versionText: some View {
        if !WatchBuildInfo.versionLine.isEmpty {
            Text(WatchBuildInfo.versionLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// 版號：打包出來的 Info.plist 的 CFBundleShortVersionString（＝專案層 MARKETING_VERSION）、
/// CFBundleVersion（＝CURRENT_PROJECT_VERSION）。四個 target 同號（pbxwatch_check F 段）。
enum WatchBuildInfo {
    static var versionLine: String {
        line(short: infoString("CFBundleShortVersionString"), build: infoString("CFBundleVersion"))
    }

    /// 「版本 25.573（1326）」；沒有 build＝「版本 25.573」；沒有版本＝「build 1326」；都沒有＝空字串。
    /// 跟 scratchpad/watch/build/v0/sim_v0.py 的 version_line 一模一樣（6 個例子在 sim §4）
    static func line(short rawShort: String, build rawBuild: String) -> String {
        let short = rawShort.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = rawBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty { return build.isEmpty ? "" : "build \(build)" }
        if build.isEmpty { return "版本 \(short)" }
        return "版本 \(short)（\(build)）"
    }

    private static func infoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}
