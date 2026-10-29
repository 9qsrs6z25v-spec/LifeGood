import Foundation
import SwiftUI
import WatchKit

// MARK: - 手錶 App 進入點（手錶 v1，v25.574；watch/judge.md §2.0、§5.3；watch/build/v1/brief.md G2-1）
//
// 只屬於「LifeGoodWatch」target（com.lifegood.app.watchkitapp，watchOS 11.0，依附 iPhone 的 LifeGood）。
// v0（25.573）是一頁「手錶版準備中」；v1 換成 RootView（① 今天、② 錢垂直翻頁，judge §2.0）。
// WatchAppDelegate（WKApplicationDelegateAdaptor）在 init 就把 WCSession 的 delegate 設成 WatchSync 並 activate，
// 背景收包照 Apple 範例收尾（judge §5.3-4、§7.8-7）；通知〔看議程〕的 delegate 也在那裡裝。
//
// 寫法守則（judge §7.8）：手錶 target 只准 import SwiftUI、WidgetKit、WatchKit、WatchConnectivity、Foundation
// （UserNotifications 只有 WatchNotificationDelegate.swift）；不准 UIKit、ActivityKit、CoreImage、Speech、AlarmKit、CloudKit。

@main
struct LifeGoodWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 版號：打包出來的 Info.plist 的 CFBundleShortVersionString（＝專案層 MARKETING_VERSION）、
/// CFBundleVersion（＝CURRENT_PROJECT_VERSION）。四個 target 同號（pbxwatch_check F 段）。
/// v1 起只有手錶設定（SettingsSheet）最下面用。
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
