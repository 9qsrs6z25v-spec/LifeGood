import Foundation
import AVFoundation
import UIKit

// MARK: - 跑步語音（健康 v7，v25.557；health/judge.md §6 v7、build/v7/brief.md §G1-12）
//
// 只屬於 App target（A01C000001000002）。主控建空殼、簽章不准改；G1 填內容。
//
// 誰叫這裡（主控契約）：
// • RunTracker.store()：走滿整公里那一刻 kmDone(sport:kmTimes:)（騎車只有 5 的倍數有字：WorkoutFacts.voiceKm）
// • RunTracker.autoPauseNow／autoResumeNow：autoPaused(sport:)、autoResumed(sport:)（「自動暫停。」「繼續。」；手動暫停不講）
// • RunTracker.finish()／cancel()：stopAll()（不講了、音樂音量還原）
//
// 怎麼講：AVSpeechSynthesizer＋AVSpeechSynthesisVoice(language: "zh-TW")（繁中女聲）、系統預設語速。
// • 講的時候音樂自動變小聲：AVAudioSession .playback／.voicePrompt／[.duckOthers, .interruptSpokenAudioAndMixWithOthers]
//   （Apple 給導航、運動提示的設定：音樂變小聲、Podcast 這種講話的先停一下），要講的那一句才打開聲音（setActive(true)）。
// • 講完還原：排著的都講完（pending 0、synth 也沒在講）才 setActive(false, options: .notifyOthersOnDeactivation)，
//   音樂 App 收到通知把音量調回來。系統剛講完時聲音偶爾還在收尾（I/O 還沒停，setActive(false) 會失敗）：晚 0.4 秒再關，最多 3 次。
// • 開不起來（電話中、別的 App 占著）：這一句不講、不報錯，下一公里照講。
// • RunSport.voiceOn 講的時候才讀：跑到一半從「⋯」關掉，下一公里就不講。
// • 打包出來的 Info.plist 沒有 audio 背景模式（hasAudioBackgroundMode）時，App 不在前景（鎖著螢幕）就不講：不閃退、不報錯
//   （沒有 audio 背景模式在背景開聲音會失敗；App 開著時照講）。
// • 實機清單（U2 P2-8，論壇有人回報過）：鎖屏那一瞬間正在講的那一句會不會被切斷、講完音樂有沒有恢復音量；
//   AirPods＋Spotify／Apple Music；電話、Siri 講話時那一句不講就好、掛掉之後下一公里照講。

@MainActor
final class RunVoice: NSObject {

    static let shared = RunVoice()

    /// 打包出來的 Info.plist 的 UIBackgroundModes 真的有 audio 才為 true（照 RunTracker.hasLocationBackgroundMode 的寫法；
    /// 這個鍵寫在 LifeGood/Info.plist，v25.533 教訓：寫在 pbxproj 不會進去）。沒有的話鎖著螢幕就不講。
    /// 跑步畫面「⋯」的語音開關說明也讀它（G2）
    static let hasAudioBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("audio")
    }()

    /// 唸的人。要一直留著（系統不會幫你留，放掉了講到一半就停）
    private let synth = AVSpeechSynthesizer()
    /// 還沒講完的句數（say 加一；講完、被停掉的回呼減一；stopAll 歸零）。只是提示：真的關聲音前還會看 synth.isSpeaking
    private var pending = 0
    /// 我們把聲音打開了（setActive(true) 成功、還沒關成功）
    private var sessionActive = false

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// 走滿第 kmTimes.count 公里那一刻（RunTracker.store）。要講的字＝WorkoutFacts.voiceKm(sport:kmTimes:)（nil 不講）
    func kmDone(sport: RunSport, kmTimes: [Double]) {
        guard let text = WorkoutFacts.voiceKm(sport: WorkoutSport(sport), kmTimes: kmTimes) else { return }
        say(text)
    }

    /// 自動暫停那一刻：「自動暫停。」（WorkoutFacts.voiceAutoPause）
    func autoPaused(sport: RunSport) {
        say(WorkoutFacts.voiceAutoPause)
    }

    /// 自動繼續那一刻：「繼續。」（WorkoutFacts.voiceAutoResume）
    func autoResumed(sport: RunSport) {
        say(WorkoutFacts.voiceAutoResume)
    }

    /// 完成、放棄：還在講的停掉、排著的不講，音樂音量還原
    func stopAll() {
        if synth.isSpeaking || synth.isPaused {
            _ = synth.stopSpeaking(at: .immediate)
        }
        pending = 0
        deactivate()
    }

    // MARK: 內部

    /// 講一句：語音關著、或沒有 audio 背景模式又不在前景（鎖著螢幕）就不講；聲音開不起來也不講
    private func say(_ text: String) {
        guard RunSport.voiceOn else { return }
        if !Self.hasAudioBackgroundMode && UIApplication.shared.applicationState != .active { return }
        if synth.isPaused {
            // 被系統停在一半（電話、Siri 插進來）：排在它後面的永遠講不到，先清掉（這一句照講）
            _ = synth.stopSpeaking(at: .immediate)
            pending = 0
        } else if !synth.isSpeaking {
            pending = 0                                    // 沒在講：之前漏掉的回呼不算（不然聲音永遠不關、音樂一直小聲）
        }
        guard activate() else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        pending += 1
        synth.speak(u)
    }

    /// 打開聲音（音樂變小聲）。正在講、排著的還沒講完：已經開著，直接回 true；
    /// 沒有排著的時候每次都重設一次（電話插進來時系統會把我們的聲音關掉，旗標可能是舊的；對已經開著的再 setActive(true) 沒有關係）。
    /// 開不起來（電話中、別的 App 占著、沒有 audio 背景模式又在背景）回 false：這一句不講、不報錯
    private func activate() -> Bool {
        if sessionActive && pending > 0 { return true }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try s.setActive(true)
            sessionActive = true
            return true
        } catch {
            return false
        }
    }

    /// 關聲音、通知音樂 App 把音量調回來（沒開過什麼都不碰）。
    /// 聲音還在收尾（I/O 還沒停）時 setActive(false) 會失敗：晚 0.4 秒再試，最多 3 次；那時又有要講的就不關（講完那一句會再關）
    private func deactivate(retry: Int = 0) {
        guard sessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        } catch {
            guard retry < 3 else {
                sessionActive = false                      // 放棄：下一句會重新打開、講完再關
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard self.pending == 0, !self.synth.isSpeaking else { return }
                self.deactivate(retry: retry + 1)
            }
        }
    }

    /// 講完（或被停掉）一句：排著的都講完了才關聲音。
    /// 系統剛回講完時 isSpeaking 偶爾還是 true：0.5 秒後再看一次（不然音樂一直是小聲的）
    fileprivate func oneDone() {
        pending = max(0, pending - 1)
        guard pending == 0 else { return }
        if !synth.isSpeaking {
            deactivate()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard self.pending == 0, !self.synth.isSpeaking else { return }
            self.deactivate()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate（照 RunTracker 的 CLLocationManagerDelegate 寫法：nonisolated＋Task @MainActor）

extension RunVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in RunVoice.shared.oneDone() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in RunVoice.shared.oneDone() }
    }
}
