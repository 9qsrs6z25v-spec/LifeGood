import Foundation

// MARK: - Code 39 條碼（手錶 v2，v25.576；watch/judge.md §2.8；watch/build/v2/brief.md §2）
//
// 只屬於 LifeGoodWatch。手錶沒有 Core Image（U3 §9-7），手機條碼（「/ABC1234」）自己畫：這裡算每一條黑條的位置，
// BarcodePage 用 SwiftUI Canvas 畫。規格寫死（judge §2.8）：
//   • 最細的線（窄條）1 個單位，寬條＝窄條 2.5 倍；字跟字之間空 1 個窄條；兩邊留白各 10 個窄條
//   • 前後加起訖字「*」：「*/ABC1234*」10 個字，每個字 6 窄＋3 寬＝13.5 單位，加 9 個間隔＝144 單位，加留白＝164
//   • BarcodePage 一個單位畫 1 點（46mm 橫的 164 點）；轉 90° 時用螢幕長邊放大
// ⚠️ 下面那張表是手打的、iPhone 這邊從來沒畫過這個條碼、這裡又沒有編譯器：
//    scratchpad/watch/build/v2/code39_check.py 會把這張表抽出來跟標準表（python-barcode 0.15.1）逐字比，
//    再照 bars(for:) 一樣的算法畫成 PNG，用條碼解碼器（zxing-cpp）讀回「/ABC1234」。改了這個檔一定要重跑。

enum Code39 {
    /// 寬條是窄條的幾倍
    static let wideRatio: Double = 2.5
    /// 字跟字之間空幾個窄條
    static let gap: Double = 1
    /// 兩邊各留白幾個窄條
    static let quietZone: Double = 10
    /// 起訖字
    static let guardCharacter: Character = "*"

    /// 每個字 9 個元素：條、空、條、空、條、空、條、空、條；n＝窄、w＝寬（每個字剛好 3 個寬）
    static let patterns: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw", "3": "wnwwnnnnn",
        "4": "nnnwwnnnw", "5": "wnnwwnnnn", "6": "nnwwwnnnn", "7": "nnnwnnwnw",
        "8": "wnnwnnwnn", "9": "nnwwnnwnn",
        "A": "wnnnnwnnw", "B": "nnwnnwnnw", "C": "wnwnnwnnn", "D": "nnnnwwnnw",
        "E": "wnnnwwnnn", "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn",
        "I": "nnwnnwwnn", "J": "nnnnwwwnn", "K": "wnnnnnnww", "L": "nnwnnnnww",
        "M": "wnwnnnnwn", "N": "nnnnwnnww", "O": "wnnnwnnwn", "P": "nnwnwnnwn",
        "Q": "nnnnnnwww", "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn", "X": "nwnnwnnnw",
        "Y": "wwnnwnnnn", "Z": "nwwnwnnnn",
        "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn", "$": "nwnwnwnnn",
        "/": "nwnwnnnwn", "+": "nwnnnwnwn", "%": "nnnwnwnwn", "*": "nwnnwnwnn"
    ]

    /// 一條黑條：從條碼左邊（不含留白）算起第幾個單位、多寬（單位＝窄條寬）
    struct Bar: Equatable {
        var x: Double
        var width: Double
    }

    /// 每個字都編得了（不含「*」：起訖字只能在頭尾）
    static func canEncode(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 != guardCharacter && patterns[$0] != nil }
    }

    /// 「*」＋text＋「*」每一條黑條的位置（不含留白，x 從 0 起）。有編不了的字回空陣列
    static func bars(for text: String) -> [Bar] {
        guard canEncode(text) else { return [] }
        let full: [Character] = [guardCharacter] + Array(text) + [guardCharacter]
        var out: [Bar] = []
        var x: Double = 0
        for (index, ch) in full.enumerated() {
            guard let pattern = patterns[ch] else { return [] }
            for (i, element) in pattern.enumerated() {
                let width: Double = element == "w" ? wideRatio : 1
                if i % 2 == 0 {
                    out.append(Bar(x: x, width: width))
                }
                x += width
            }
            if index < full.count - 1 {
                x += gap
            }
        }
        return out
    }

    /// 條碼本身多寬（單位；不含留白）：「/ABC1234」＝144。編不了回 0
    static func width(for text: String) -> Double {
        guard canEncode(text) else { return 0 }
        let count = Double(text.count + 2)
        let perChar: Double = 6 + 3 * wideRatio
        return count * perChar + (count - 1) * gap
    }

    /// 加上兩邊留白的總寬（單位）：「/ABC1234」＝164
    static func totalWidth(for text: String) -> Double {
        let w = width(for: text)
        return w > 0 ? w + 2 * quietZone : 0
    }
}
