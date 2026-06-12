import Foundation
import Combine

/// 完整備份匯出進度（給底部導覽顯示細進度條用）。
final class ExportProgressModel: ObservableObject {
    static let shared = ExportProgressModel()
    @Published var isExporting = false
    @Published var fraction: Double = 0   // 0...1
    private init() {}

    @MainActor func start() { fraction = 0; isExporting = true }
    @MainActor func update(_ f: Double) { fraction = min(1, max(0, f)) }
    @MainActor func finish() { fraction = 1; isExporting = false }
}

/// 完整備份單一檔格式（.lifegood）：零依賴、可重新匯入、串流寫入不爆記憶體。
///
/// 檔案結構：
///   [magic 8B "LGBKP001"]
///   [manifestLength UInt64 little-endian, 8B]
///   [manifest JSON]
///   [附件1 bytes][附件2 bytes]…  ← 順序與 manifest.attachments 對應，各取 size 位元組
///
/// manifest 內含完整的結構化資料（UnifiedExport）+ 附件清單（資料夾 / 檔名 / 大小）。

struct BackupAttachment: Codable {
    var directory: String
    var fileName: String
    var size: Int
}

struct BackupManifest: Codable {
    var formatVersion: Int
    var createdAt: Date
    var unified: UnifiedExport
    var attachments: [BackupAttachment]
}

enum FullBackup {
    static let fileExtension = "lifegood"
    private static let magic = "LGBKP001"   // 8 bytes (ASCII)
    private static let magicData: Data = Data(magic.utf8)  // UTF-8 encoding of ASCII never fails; stored once

    enum BackupError: Error { case badFormat, writeFailed }

    /// 是否為完整備份檔（用前 8 bytes 的 magic 判斷，不讀整檔）
    static func isBackupFile(url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let head = (try? fh.read(upToCount: 8)) ?? Data()
        return head == magicData
    }

    // MARK: - 匯出（打包）

    /// 產生完整備份檔，回傳暫存檔 URL（給分享）。串流寫入：每個附件單獨讀寫，不整包進記憶體。
    /// unified 由呼叫端在主執行緒先用 UnifiedExport.build 準備好傳入，本函式只做檔案 I/O，可在背景執行。
    static func export(unified: UnifiedExport, progress: ((Double) -> Void)? = nil) throws -> URL {
        let fm = FileManager.default
        progress?(0)

        // 收集所有模組的附件檔
        let files = gatherAttachmentFiles()
        var manifestAtts: [BackupAttachment] = []
        for f in files {
            let size = (try? fm.attributesOfItem(atPath: f.url.path)[.size] as? Int) ?? 0
            manifestAtts.append(BackupAttachment(directory: f.dir, fileName: f.name, size: size))
        }

        let manifest = BackupManifest(formatVersion: 1, createdAt: Date(),
                                      unified: unified, attachments: manifestAtts)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let manifestData = try enc.encode(manifest)

        let outURL = fm.temporaryDirectory
            .appendingPathComponent("LifeGood_完整備份_\(stamp()).\(fileExtension)")
        try? fm.removeItem(at: outURL)
        guard fm.createFile(atPath: outURL.path, contents: nil) else { throw BackupError.writeFailed }
        let fh = try FileHandle(forWritingTo: outURL)
        defer { try? fh.close() }

        try fh.write(contentsOf: magicData)
        try fh.write(contentsOf: uint64LE(UInt64(manifestData.count)))
        try fh.write(contentsOf: manifestData)
        // 逐檔附加（單檔讀寫，記憶體只佔一張）；以整數百分比節流回報進度
        let total = files.count
        var lastPct = -1
        for (i, f) in files.enumerated() {
            if let data = try? Data(contentsOf: f.url, options: .mappedIfSafe) {
                try fh.write(contentsOf: data)
            }
            if total > 0 {
                let pct = Int(Double(i + 1) / Double(total) * 100)
                if pct != lastPct { lastPct = pct; progress?(Double(i + 1) / Double(total)) }
            }
        }
        progress?(1)
        return outURL
    }

    // MARK: - 匯入（還原）

    /// 從備份檔還原：先重用 UnifiedImporter 還原結構化資料，再把附件寫回各資料夾。串流讀取。
    static func restore(from url: URL, mode: UnifiedImporter.Mode,
                        expense: ExpenseStore, finance: FinanceStore, life: LifeStore) throws -> String {
        let fm = FileManager.default
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }

        guard let head = try fh.read(upToCount: 8), head == magicData else { throw BackupError.badFormat }
        guard let lenData = try fh.read(upToCount: 8), lenData.count == 8 else { throw BackupError.badFormat }
        let manifestLen = Int(readUInt64LE(lenData))
        guard manifestLen > 0, let manifestData = try fh.read(upToCount: manifestLen),
              manifestData.count == manifestLen else { throw BackupError.badFormat }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let manifest = try dec.decode(BackupManifest.self, from: manifestData)

        // 1) 結構化資料 → 重用 UnifiedImporter（合併 / 取代）
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let unifiedData = try enc.encode(manifest.unified)
        let result = UnifiedImporter.importData(data: unifiedData, mode: mode,
                                                expense: expense, finance: finance, life: life)

        // 2) 附件寫回各資料夾（依序，依 size 取位元組）
        var written = 0
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            for att in manifest.attachments {
                guard att.size >= 0, let bytes = try fh.read(upToCount: att.size),
                      bytes.count == att.size else { break }
                let dirURL = docs.appendingPathComponent(att.directory, isDirectory: true)
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                let dest = dirURL.appendingPathComponent(att.fileName)
                try? bytes.write(to: dest)
                written += 1
            }
        }
        return "\(result.summary)；照片 / 文件 \(written) 個"
    }

    // MARK: - Helpers

    private static func gatherAttachmentFiles() -> [(dir: String, name: String, url: URL)] {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var out: [(String, String, URL)] = []
        for dir in CloudKitManager.photoDirectories {
            let dirURL = docs.appendingPathComponent(dir, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dirURL.path) else { continue }
            for n in names where !n.hasPrefix(".") {
                out.append((dir, n, dirURL.appendingPathComponent(n)))
            }
        }
        return out
    }

    private static func uint64LE(_ x: UInt64) -> Data {
        var d = Data(count: 8)
        for i in 0..<8 { d[i] = UInt8((x >> (8 * UInt64(i))) & 0xFF) }
        return d
    }

    private static func readUInt64LE(_ d: Data) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(d[d.startIndex + i]) << (8 * UInt64(i)) }
        return v
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
