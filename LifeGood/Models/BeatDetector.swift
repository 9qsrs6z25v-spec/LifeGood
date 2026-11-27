import Foundation
import AVFoundation

// MARK: - 節拍偵測（v25.486）
//
// 目的：讓動態相簿換照片的時機踩在歌曲的拍子上。
//
// ── 能分析什麼、不能分析什麼 ──
// 我們拿得到波形的只有 MPMediaItem.assetURL 指得到的檔案：你自己買的、
// 匯入的、從 CD 轉的那些。**Apple Music 串流下載的歌是加密的，assetURL 是 nil**，
// 任何 App 都讀不到它的波形（能讀就等於能側錄）。那種情況留給手動「跟拍」。
//
// ── 怎麼算 ──
// 1. 用 AVAssetReader 把前 60 秒解成 11025Hz 單聲道 PCM（夠用又快）
// 2. 每 512 個取樣算一次 RMS 能量 → 得到一條每秒約 21.5 點的能量包絡
// 3. 相鄰能量的「正向變化量」＝起音強度（onset flux）：鼓點、重拍會凸起來
// 4. 對 onset 做自相關，找 60～180 BPM 範圍內相關性最高的週期
// 5. 用那個週期去「梳」整條 onset，分數最高的相位就是第一個拍點
//
// 這是教科書等級的做法，不是什麼神奇演算法：節奏明確的歌（流行、電子）準，
// 自由速度的抒情歌或古典會抓不準——所以 confidence 低於門檻時寧可不要卡點，
// 亂卡比不卡更難看。

/// 一首歌的節拍網格
struct BeatGrid: Equatable {
    let bpm: Double
    /// 第一個拍點落在歌曲的第幾秒
    let firstBeat: Double
    /// 0...1。節奏越明確越高；低於門檻就不要拿來卡點。
    let confidence: Double

    /// 一拍幾秒
    var interval: Double { 60.0 / max(bpm, 1) }

    /// 從 time 之後的下一個「每 beats 拍」的落點
    func next(after time: Double, every beats: Int) -> Double {
        let period = interval * Double(max(1, beats))
        let k = ((time - firstBeat) / period).rounded(.down) + 1
        return firstBeat + k * period
    }

    /// 現在是第幾拍（用來做每拍的脈動）
    func beatIndex(at time: Double) -> Int {
        Int(((time - firstBeat) / interval).rounded(.down))
    }
}

enum BeatDetector {
    /// 分析用的取樣率與每格長度。11025Hz 對節拍偵測綽綽有餘，
    /// 而且解碼量只有原始檔的四分之一。
    private static let sampleRate: Double = 11025
    private static let hop = 512

    /// 把檔案分析成節拍網格。拿不到波形或節奏太模糊就回 nil。
    static func analyze(url: URL, seconds limit: Double = 60) async -> BeatGrid? {
        await Task.detached(priority: .userInitiated) { () -> BeatGrid? in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: sampleRate
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            reader.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: limit, preferredTimescale: 600))
            guard reader.startReading() else { return nil }

            // 1 + 2：解碼並算能量包絡
            var envelope: [Float] = []
            var carry: [Int16] = []
            carry.reserveCapacity(hop * 4)
            while let buffer = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                                  totalLengthOut: &length,
                                                  dataPointerOut: &pointer) == kCMBlockBufferNoErr,
                      let pointer else { continue }
                let count = length / MemoryLayout<Int16>.size
                pointer.withMemoryRebound(to: Int16.self, capacity: count) { ptr in
                    carry.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
                }
                var cursor = 0
                while carry.count - cursor >= hop {
                    var sum: Float = 0
                    for i in cursor..<(cursor + hop) {
                        let v = Float(carry[i]) / 32768
                        sum += v * v
                    }
                    envelope.append((sum / Float(hop)).squareRoot())
                    cursor += hop
                }
                if cursor > 0 { carry.removeFirst(cursor) }
            }
            reader.cancelReading()

            guard envelope.count > 60 else { return nil }

            // 3：起音強度（只取變大的那一半，變小不是鼓點）
            var flux = [Float](repeating: 0, count: envelope.count)
            for i in 1..<envelope.count {
                flux[i] = max(0, envelope[i] - envelope[i - 1])
            }
            let mean = flux.reduce(0, +) / Float(flux.count)
            guard mean > 0 else { return nil }
            // 去掉直流分量，自相關才不會被「整首都很大聲」主導
            let centered = flux.map { $0 - mean }

            // 4：自相關找週期
            let frameRate = sampleRate / Double(hop)        // 每秒幾格 ≈ 21.5
            let minLag = max(2, Int((60.0 / 180.0) * frameRate))
            let maxLag = min(centered.count / 2, Int((60.0 / 60.0) * frameRate))
            guard maxLag > minLag else { return nil }

            var scores: [Float] = []
            var bestLag = minLag
            var bestScore = -Float.greatestFiniteMagnitude
            for lag in minLag...maxLag {
                var sum: Float = 0
                var i = lag
                while i < centered.count {
                    sum += centered[i] * centered[i - lag]
                    i += 1
                }
                let value = sum / Float(centered.count - lag)
                scores.append(value)
                if value > bestScore { bestScore = value; bestLag = lag }
            }

            var bpm = 60.0 * frameRate / Double(bestLag)
            // 八度修正：自相關很常抓到一半或兩倍。把結果拉回常見範圍。
            if bpm < 80 && bpm * 2 <= 180 { bpm *= 2 }
            if bpm > 160 { bpm /= 2 }

            // 5：用週期去梳 onset，找相位
            let period = max(1, Int((60.0 / bpm * frameRate).rounded()))
            var bestPhase = 0
            var bestPhaseScore = -Float.greatestFiniteMagnitude
            for phase in 0..<period {
                var sum: Float = 0
                var i = phase
                while i < flux.count { sum += flux[i]; i += period }
                if sum > bestPhaseScore { bestPhaseScore = sum; bestPhase = phase }
            }

            // 信心：最高的那個週期比其他週期突出多少
            let avg = scores.reduce(0, +) / Float(scores.count)
            let variance = scores.reduce(Float(0)) { $0 + ($1 - avg) * ($1 - avg) } / Float(scores.count)
            let sd = variance.squareRoot()
            let confidence = sd > 0
                ? min(1.0, max(0.0, Double((bestScore - avg) / (3 * sd))))
                : 0.0

            return BeatGrid(bpm: bpm,
                            firstBeat: Double(bestPhase) / frameRate,
                            confidence: confidence)
        }.value
    }

    /// 手動跟拍：使用者點幾下，算出 BPM。
    ///
    /// Apple Music 的保護曲目讀不到波形，這是唯一的辦法；
    /// 而且就算分析得到，使用者覺得不對時也該有手動蓋過去的路。
    static func bpm(fromTaps taps: [Date]) -> Double? {
        guard taps.count >= 4 else { return nil }
        let recent = Array(taps.suffix(8))
        var intervals: [Double] = []
        for i in 1..<recent.count {
            intervals.append(recent[i].timeIntervalSince(recent[i - 1]))
        }
        // 太快太慢的那幾下當作手滑，丟掉
        let valid = intervals.filter { $0 > 0.25 && $0 < 2.0 }
        guard valid.count >= 3 else { return nil }
        let average = valid.reduce(0, +) / Double(valid.count)
        return 60.0 / average
    }
}
