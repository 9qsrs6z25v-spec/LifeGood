import Foundation
import AVFoundation

// MARK: - 跑步語音（手錶 v4，v25.580；watch/judge.md §2.11「語音」、§7.2、§7.8-17；watch/build/v4/brief.md §2、G2-3）
//
// 只屬於 LifeGoodWatch（名字前面加 Watch：iPhone 已經有一個 RunVoice）。**骨架（主控寫）：對外的名字、型別、參數不准改；G2 照 iPhone LifeGood/Models/RunVoice.swift 填內容。**
// 講什麼：WorkoutManager 給字（WatchRunFacts.voiceKm「3 公里，這一公里 6 分 10 秒，總時間 18 分 25 秒，平均配速 6 分 08 秒。」、
// voiceAutoPause「自動暫停。」、voiceAutoResume「繼續。」；跟 iPhone 一字不差）；語音開關由 WorkoutManager 先看（voiceOn），
// 這裡不讀設定。
// 怎麼講：AVSpeechSynthesizer＋AVSpeechSynthesisVoice(language: "zh-TW")；**手錶上找不到 zh-TW 嗓音就不講**（只震動，
// 設定頁寫「這支手錶沒有台灣中文語音，每公里只震動」）。
// 聲音：AVAudioSession .playback＋mode .voicePrompt＋options [.duckOthers]（AirPods 上的 Podcast、音樂只是變小聲，主控 §13 決定；
// iPhone 多一個 .interruptSpokenAudioAndMixWithOthers 會讓 Podcast 先停一下——手錶這版不加，實機聽了再說）。要講才
// setActive(true)，排著的都講完才 setActive(false, options: .notifyOthersOnDeactivation)（音量還原）；收尾失敗晚 0.4 秒再試、最多 3 次
// （照抄 iPhone 的 deactivate）。開不起來（電話中）這一句不講、不報錯。
// 打包出來的 Info.plist 沒有 UIBackgroundModes 的 audio（hasAudioBackgroundMode）：不講（不閃退）。
// 每個 AVAudioSession 選項在 watchOS 都查過（watch/build/v4/brief.md §1）：setCategory(_:mode:options:) watchOS 3、
// .voicePrompt watchOS 5、.duckOthers、setActive(_:options:) watchOS 2、.notifyOthersOnDeactivation。
//
// [G2 填好] 結構照抄 iPhone RunVoice：say（被系統停在一半先清、activate、speak）、activate（排著的還沒講完就不重設）、
// deactivate(retry:)（0.4 秒、最多 3 次）、oneDone（0.5 秒再看一次）、delegate 兩支 nonisolated＋Task @MainActor。
// 跟 iPhone 不同的只有三處：選項只有 .duckOthers；沒有 App 在不在前景的判斷（手錶跑步中 App 一直在背景活著，
// 沒有 audio 背景模式就一律不講）；嗓音找不到 zh-TW 就不講（iPhone 照講，系統會找替代）。

@MainActor
final class WatchRunVoice: NSObject {
    static let shared = WatchRunVoice()

    /// 嗓音的語言
    static let language = "zh-TW"

    /// 打包出來的 Info.plist 的 UIBackgroundModes 真的有 audio 才為 true（同 iPhone RunVoice.hasAudioBackgroundMode）
    static let hasAudioBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        return modes.contains("audio")
    }()

    /// 手錶上有台灣中文嗓音（AVSpeechSynthesisVoice(language: "zh-TW") 不是 nil）
    static var hasTaiwanVoice: Bool {
        AVSpeechSynthesisVoice(language: language) != nil
    }

    /// 手錶上找得到的中文嗓音（語言 zh 開頭）：「美佳（zh-TW）」，照名字排；手錶設定最下面列給你看（judge §2.11）
    static func chineseVoiceNames() -> [String] {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        return voices.map { $0.name + "（" + $0.language + "）" }.sorted()
    }

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

    /// 講一句（WorkoutManager 已經看過 voiceOn）：沒有 zh-TW 嗓音、沒有 audio 背景模式、聲音開不起來都不講
    func say(_ text: String) {
        guard !text.isEmpty, Self.hasAudioBackgroundMode,
              let voice = AVSpeechSynthesisVoice(language: Self.language) else { return }
        if synth.isPaused {
            // 被系統停在一半（電話、Siri 插進來）：排在它後面的永遠講不到，先清掉（這一句照講）
            _ = synth.stopSpeaking(at: .immediate)
            pending = 0
        } else if !synth.isSpeaking {
            pending = 0                                    // 沒在講：之前漏掉的回呼不算（不然聲音永遠不關、Podcast 一直小聲）
        }
        guard activate() else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        pending += 1
        synth.speak(u)
    }

    /// 結束、丟掉：還在講的停掉、排著的不講、音量還原
    func stopAll() {
        if synth.isSpeaking || synth.isPaused {
            _ = synth.stopSpeaking(at: .immediate)
        }
        pending = 0
        deactivate()
    }

    // MARK: 內部（照抄 iPhone RunVoice）

    /// 打開聲音（Podcast、音樂變小聲）。正在講、排著的還沒講完：已經開著，直接回 true；
    /// 沒有排著的時候每次都重設一次（電話插進來時系統會把我們的聲音關掉，旗標可能是舊的）。
    /// 開不起來（電話中、別的 App 占著）回 false：這一句不講、不報錯
    private func activate() -> Bool {
        if sessionActive && pending > 0 { return true }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try s.setActive(true)
            sessionActive = true
            return true
        } catch {
            return false
        }
    }

    /// 關聲音、通知 Podcast／音樂 App 把音量調回來（沒開過什麼都不碰）。
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
    /// 系統剛回講完時 isSpeaking 偶爾還是 true：0.5 秒後再看一次（不然 Podcast 一直是小聲的）
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

// MARK: - AVSpeechSynthesizerDelegate（照 iPhone RunVoice：nonisolated＋Task @MainActor）

extension WatchRunVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in WatchRunVoice.shared.oneDone() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in WatchRunVoice.shared.oneDone() }
    }
}
