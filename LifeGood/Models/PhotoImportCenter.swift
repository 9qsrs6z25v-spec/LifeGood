import SwiftUI
import PhotosUI
import ActivityKit
import UIKit

// MARK: - 照片匯入中心（v25.483）
//
// 使用者回報：在景點卡按了「從相簿多選」，41 張照片卡在那個畫面動不了，
// 因為 iCloud 的原圖要一張一張下載回來。
//
// 原本的匯入是掛在相片廊那個 View 上的：畫面一消失（.onDisappear）就取消，
// 而且**已經寫進磁碟的那幾張會被刪掉**——那是刻意的，不然寫好的檔案會變成
// 沒有任何紀錄引用的孤兒。問題在於「離開畫面」與「丟掉成果」被綁在一起了。
//
// 解法是把「要寫回哪裡」交出來：呼叫端給一個 commit 閉包（例如景點照片是
// 寫回 LifeStore 的那一站），匯入就不再屬於那個畫面，而是屬於這個中心。
// 畫面關掉、換頁、甚至跳出 App 都不影響，寫回去的對象還在。
//
// ⚠️ 只有「寫回 store」的相片廊可以這樣做。記帳表單那種「按了儲存才落地」的
//    畫面不行——那裡的 fileNames 是表單自己的暫存，表單一關就沒有人認領了，
//    所以那些呼叫端不傳 commit，維持原本「離開就取消並清掉」的行為。
final class PhotoImportCenter: ObservableObject {
    static let shared = PhotoImportCenter()

    private struct Job {
        let items: [PhotosPickerItem]
        let label: String
        let save: (Data) -> String?
        let commit: ([String]) -> Void
    }

    /// 有沒有正在匯入（底部那條細進度條靠它決定出不出現）
    @Published private(set) var isImporting = false
    /// 已完成張數 / 總張數——跨多批累計，使用者連續選了兩批也只會看到一條
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// 目前這一批要存到哪裡（例「景點照片」）
    @Published private(set) var label = ""

    private var queue: [Job] = []
    private var worker: Task<Void, Never>?
    private var activity: Activity<PhotoImportAttributes>?

    private init() {
        // 跳出 App 的那一刻才開靈動島：還在 App 裡的時候，底部那條細進度條
        // 已經在講同一件事，兩個一起出現只是重複。
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { _ in
            Task { @MainActor in PhotoImportCenter.shared.startActivityIfNeeded() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { _ in
            Task { @MainActor in await PhotoImportCenter.shared.endActivity() }
        }
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(done) / Double(total)))
    }

    /// 「正在取得照片 40 / 41」
    var statusText: String {
        guard total > 0 else { return "" }
        return "正在取得照片 \(min(done + 1, total)) / \(total)"
    }

    // MARK: 排程

    /// 排一批照片進來。畫面可以立刻關掉，匯入會自己跑完再寫回去。
    ///
    /// - Parameters:
    ///   - save: 把原始資料寫成檔案並回傳檔名（各模型自己的 savePhoto）
    ///   - commit: 全部寫完之後要把檔名掛到哪裡。**這個閉包不能依賴畫面還活著**
    ///             ——它會在匯入結束時才被呼叫，那時使用者可能早就換了好幾頁。
    @MainActor
    func enqueue(items: [PhotosPickerItem],
                 label: String,
                 save: @escaping (Data) -> String?,
                 commit: @escaping ([String]) -> Void) {
        guard !items.isEmpty else { return }
        queue.append(Job(items: items, label: label, save: save, commit: commit))
        total += items.count
        self.label = label
        isImporting = true
        if worker == nil {
            worker = Task { [weak self] in await self?.drain() }
        }
    }

    @MainActor
    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            label = job.label
            var added: [String] = []
            for item in job.items {
                let save = job.save
                // 下載與寫檔都在背景：loadTransferable 會把 iCloud 的原圖整張拉回來，
                // 跑在主執行緒上的話整個 App 會卡住。
                let name: String? = await Task.detached(priority: .userInitiated) {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        return nil
                    }
                    return save(data)
                }.value
                if let name { added.append(name) }
                done += 1
                await updateActivity()
            }
            // 一批寫完就寫回去，不要等整個佇列跑完——使用者選了兩批時，
            // 第一批不該被第二批拖著一起等。
            job.commit(added)
        }
        await finishActivity()
        isImporting = false
        done = 0
        total = 0
        label = ""
        worker = nil
    }

    // MARK: 靈動島

    @MainActor
    private func startActivityIfNeeded() {
        guard isImporting, activity == nil,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = PhotoImportAttributes.ContentState(
            done: done, total: total, label: label, finished: false)
        activity = try? Activity.request(
            attributes: PhotoImportAttributes(startedAt: Date()),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
    }

    @MainActor
    private func updateActivity() async {
        guard let activity else { return }
        await activity.update(ActivityContent(
            state: PhotoImportAttributes.ContentState(
                done: done, total: total, label: label, finished: false),
            staleDate: nil))
    }

    /// 全部跑完：先把「完成」推上去，幾秒後才讓它自己收掉——
    /// 直接消失的話，使用者回頭看靈動島只會發現東西不見了，不知道是成功還是壞了。
    @MainActor
    private func finishActivity() async {
        guard let activity else { return }
        let final = PhotoImportAttributes.ContentState(
            done: total, total: total, label: label, finished: true)
        await activity.end(ActivityContent(state: final, staleDate: nil),
                           dismissalPolicy: .after(Date().addingTimeInterval(4)))
        self.activity = nil
    }

    /// 回到前景：App 裡的細進度條接手，靈動島就不用占著了
    @MainActor
    private func endActivity() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
