import Foundation

// [v25.624] 水電 v5a：拍帳單照片讀度數、計費期間、應繳金額（judge_utility C19 v5 第一項、C20 Q1；research §4）。
// 這個檔只有純函式（sim_util5.py 一個函式一個函式對照）：
// - rows(from:)：Vision 讀到的一塊一塊字（UtilityBillPhotoReader 在背景執行緒讀）照位置排成一行一行。
// - parse(lines:paidOn:type:)：找標籤（「計費度數」「計費期間」「應繳總金額」「本期指數」…）旁邊的數字和日期。
//   民國年 3 位數 +1911；只收跟繳費日相差一年內的日期；「去年同期」「上期」「上月」那幾段的數字跳過；
//   有本期、上期指數時用「本期－上期」核對度數，對不上就不填度數、只提示；照片看起來是別種帳單就什麼都不填。
// - fill(_:now:)：只填空的欄（已經填了的不覆蓋，只在灰字裡說照片上是多少）；marks(...)：填進去的欄旁標「從照片讀的，請核對」。
// 不碰任何 store、不寫檔、不寫 UserDefaults、不 print／不寫 log：照片上有姓名、地址、電號，讀到的字只在記憶體、用完就丟。
// 結果只進繳費表單的 @State，使用者按〔儲存〕才照舊走 save → recordSave（不自動存）。只進 App target。
// [final] 寧可讀不到也不要填錯：日期、數字被讀壞（1B、I,590、1;590、7 0 2、|09|）整段不收、不取前段或後段；表頭夾了別的欄、
//   數字行不只一個數、上一行像一排數字、紀錄表的起訖行、斜拍又看不出斜度 → 不填；收據的金額只在帳單上確定沒有金額時才補。

/// Vision 讀到的一塊字（正規化座標，左下是 0,0）
struct UtilityOCRBox: Equatable {
    let text: String
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
    /// [review parse-1] Vision 給的四個角：上緣方向（右上角－左上角）、左緣方向（左上角－左下角），單位跟上面一樣。
    /// 0,0＝沒有（當作水平）。照片斜拍時拿來把整張轉正再分行
    var dirX: Double = 0
    var dirY: Double = 0
    var upX: Double = 0
    var upY: Double = 0
}

/// 一張照片讀到的（驗過的值；只在記憶體）
struct UtilityBillReading: Equatable {
    /// 照片看起來是別種帳單（例如電費帳單、這一期選的是水費）→ 什麼都不填，只提示
    var mismatch: Bool = false
    /// 度數：有限數、≥ 0、< 1,000,000；有本期、上期指數時已經核對過
    var usage: Double? = nil
    /// 計費期間「2026-07-13」（到 ≥ 從、≤ 186 天、兩天都跟繳費日相差一年內）
    var startKey: String? = nil
    var endKey: String? = nil
    /// 應繳總金額（> 0、< 1,000,000）
    var amount: Double? = nil
    /// 本期、上期指數（只拿來核對度數，不存）
    var currentIndex: Double? = nil
    var previousIndex: Double? = nil
    /// 有讀到計費期間，但跟繳費日差超過一年（多半是繳費日期還沒改）
    var datesOutOfRange: Bool = false
    /// 灰字提示（對不起來、有兩個不同的值、類型不對）
    var hints: [String] = []
    /// [harden-5] 照片看不出是哪一種帳單、又讀到度數或期間（或有提示）→ 灰字最後多一句「請確認上面選的是…」（不算 hints：不擋「沒找到…」那句）
    var typeNote: String? = nil
    /// [final F1] 這張照片上可能有應繳金額：有應繳金額的標籤（讀不讀得到都算），或整張有字卻斜太多讀不了（reading(boxes:)）。
    /// 這張自己沒讀到金額 → 不拿別張（超商收據）的金額來補
    var mayHaveAmount: Bool = false

    var hasAnything: Bool { usage != nil || startKey != nil || amount != nil }
    /// [review flow-1] 有度數或期間（超商收據那種只有金額的不算）
    var hasUsageOrPeriod: Bool { usage != nil || startKey != nil }
    var hasSomethingToSay: Bool { mismatch || datesOutOfRange || !hints.isEmpty }
}

/// 按〔從照片讀數字〕那一刻表單上的值（決定哪幾欄是空的）
struct UtilityPhotoFormNow: Equatable {
    let usageText: String
    let amountText: String
    /// 期間算空的：打開時沒有、也還沒點開「從」「到」（從上一期推的預設也算空的：照帳單的比較準）
    let periodIsEmpty: Bool
    /// 畫面上現在的期間（有期間才有；比「照片上的一不一樣」用）
    let startKey: String?
    let endKey: String?
}

/// 要填進表單的字（nil＝不填）＋按鈕下面的灰字
struct UtilityPhotoFill: Equatable {
    var usageText: String? = nil
    var amountText: String? = nil
    var startKey: String? = nil
    var endKey: String? = nil
    var message: String? = nil

    /// 填了度數或期間 → 「度數和計費期間」那一段要打開
    var opensUsage: Bool { usageText != nil || startKey != nil }
}

/// 哪幾欄旁邊要標「從照片讀的，請核對」（欄位還是照片讀的那個值才標；改過就不標）
struct UtilityPhotoMarks: Equatable {
    let usage: Bool
    let period: Bool
    let amount: Bool

    static let empty = UtilityPhotoMarks(usage: false, period: false, amount: false)
}

enum UtilityBillOCR {
    // MARK: 畫面上的字

    static let buttonTitle = "從照片讀數字"
    static let readingTitle = "正在讀照片…"
    static let cancelTitle = "取消"
    static let checkNote = "從照片讀的，請核對"
    static let privacyNote = "只在這支手機上讀，讀到的字不上傳、不留下"
    static let noneFound = "照片裡沒找到度數和計費期間，可以自己填"
    static let noUsage = "照片裡沒找到度數，可以自己填"
    static let noPeriod = "照片裡沒找到計費期間，可以自己填"
    static let outOfRange = "照片上的日期跟繳費日期差超過一年，先把繳費日期改對再讀一次"
    static let sameAsFilled = "照片上的數字跟已經填的一樣"
    static let indexBackwards = "照片上的本期指數比上期小，度數請看帳單自己填"
    static let amountConflict = "照片上有兩個不同的應繳金額，請自己填"
    static let periodConflict = "照片上有兩個不同的計費期間，請自己填"

    // MARK: 規則的數字

    /// 最多讀幾張（從最新那張往前）
    static let maxPhotos = 3
    /// 大圖先縮到長邊 ≤ 2000 像素再辨識
    static let maxPixel: Double = 2000
    /// [final skew] 看不出斜度時，外接矩形估出來的斜度（sin）超過這個（約 1.5°）→ 讀不到
    static let tiltMax: Double = 0.026
    /// [final skew] boxTilt 兩塊字的寬差至少這麼多才拿來算
    static let tiltMinWidthGap: Double = 0.05
    /// 日期跟繳費日相差幾天以內才收
    static let windowDays = 366
    static let maxAmount: Double = 1_000_000
    /// 度數跟「本期－上期」差多少以內算對得上
    static let indexTolerance: Double = 0.01

    /// 「去年同期」「上期」「上月」…：標籤前面、或標籤到數字中間有這些字 → 那個數字不是這一期的（research §4.4）
    /// [harden-1] 加「上一期」「上個月」「前年」「歷史」…這些比較的字（都不含「本期」；「上期指數」這種標籤本身照認）
    /// [final E1] 加「尖峰」「離峰」「夏月」：時間電價、夏月／非夏月分開的那一列只是一部分的度數（「半尖峰」「非夏月」也含在裡面）
    static let distractors: [String] = ["去年", "上期", "上次", "上月", "前期", "前次", "同期", "平均", "每度", "下期", "下次", "累計", "前月",
                                        "上一期", "前一期", "上個月", "上一次", "前一次", "上年度", "前年", "歷史", "平均每日",
                                        "尖峰", "離峰", "夏月"]
    /// [harden-4] 沒標籤的「起 ~ 訖」那一行有這些字 → 是繳費期限、代收期間，不是計費期間
    static let periodStopWords: [String] = ["期限", "代收", "繳費", "繳款", "截止", "到期"]
    /// [final B2] 有這些字的照片 → 沒標籤的起訖行不算（多半是用電紀錄表的一列）
    static let historyWords: [String] = ["紀錄", "記錄", "歷史", "近期", "近6期", "近六期"]
    /// [harden-5] 照片看不出是哪一種帳單時，水費、瓦斯費一期超過這麼多度就不填（多半是讀到電費單）
    static let unknownTypeMaxUsage: Double = 300
    static let unknownTypePrefix = "照片上看不出是電費、水費還是瓦斯費，請確認上面選的是"

    // MARK: 照片

    /// 要讀哪幾張：PDF 跳過，從最新（最後加的）那張往前最多 3 張
    static func readableNames(_ names: [String]) -> [String] {
        var images: [String] = []
        for n in names where !n.lowercased().hasSuffix(".pdf") {
            images.append(n)
        }
        return Array(images.reversed().prefix(maxPhotos))
    }

    /// 幾張照片的結果（從新到舊）：第一張有度數或期間的（[review flow-1] 只有金額的收據不算；這張自己沒有金額、也沒有
    /// 「兩個不同的金額」、[final F1] 也沒有應繳金額的標籤（有標籤卻讀不到＝金額讀壞了）→ 用別張讀到的金額 otherAmount）；
    /// 都沒有 → 讀到 otherAmount 那個金額的第一張；再沒有 → 第一張有話要說的（類型不對、日期差太遠…）；都沒有 nil
    static func pick(_ readings: [UtilityBillReading]) -> UtilityBillReading? {
        for r in readings where r.hasUsageOrPeriod {
            guard r.amount == nil, !r.mayHaveAmount, !r.hints.contains(amountConflict) else { return r }
            var m: UtilityBillReading = r
            m.amount = otherAmount(readings)
            return m
        }
        if let a = otherAmount(readings) {
            for r in readings where r.amount == a { return r }
        }
        for r in readings where r.hasSomethingToSay { return r }
        return nil
    }

    /// [final F1] 幾張照片讀到的金額：都一樣才用（兩張不一樣 → nil）；有一張的金額有標籤卻讀不到（讀壞了）→ nil（不拿收據的來補）
    static func otherAmount(_ readings: [UtilityBillReading]) -> Double? {
        var found: Double? = nil
        for o in readings {
            if o.mayHaveAmount && o.amount == nil { return nil }
            guard let a = o.amount else { continue }
            if let f = found, f != a { return nil }
            found = a
        }
        return found
    }

    // MARK: 一塊一塊的字 → 一行一行

    /// 由上往下（中線 y 大的先）；中線落在這一行第一塊的上下範圍內就算同一行；同一行由左往右、用一個空白接起來。
    /// [review parse-1] 先照字塊的斜度把整張轉正（leveled）；斜超過 45° 當作讀不到
    static func rows(from boxes: [UtilityOCRBox]) -> [String] {
        guard let level = leveled(boxes) else { return [] }
        var items: [(index: Int, box: UtilityOCRBox)] = []
        for (i, b) in level.enumerated() where !b.text.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append((index: i, box: b))
        }
        items.sort { a, b in
            let ma: Double = (a.box.minY + a.box.maxY) / 2
            let mb: Double = (b.box.minY + b.box.maxY) / 2
            if ma != mb { return ma > mb }
            if a.box.minX != b.box.minX { return a.box.minX < b.box.minX }
            return a.index < b.index
        }
        var groups: [[(index: Int, box: UtilityOCRBox)]] = []
        for item in items {
            let mid: Double = (item.box.minY + item.box.maxY) / 2
            if let anchor = groups.last?.first, mid >= anchor.box.minY, mid <= anchor.box.maxY {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        var out: [String] = []
        for g in groups {
            out.append(rowText(g))
        }
        return out
    }

    /// [review parse-1] 斜拍轉正：寬的字塊（上緣長 ≥ 左緣 2 倍）上緣斜度取中位數，每塊的中心轉回水平、寬高用上緣和左緣的長度。
    /// 沒有角的資料、斜度是 0 → 原封不動（[final skew] 但外接矩形看起來是斜的 boxTilt > tiltMax → nil）；斜超過 45° → nil（讀不到，不猜）
    static func leveled(_ boxes: [UtilityOCRBox]) -> [UtilityOCRBox]? {
        var angles: [Double] = []
        for b in boxes where b.dirX > 0 {
            let w: Double = (b.dirX * b.dirX + b.dirY * b.dirY).squareRoot()
            let h: Double = (b.upX * b.upX + b.upY * b.upY).squareRoot()
            if h > 0 && w >= 2 * h { angles.append(atan2(b.dirY, b.dirX)) }
        }
        guard !angles.isEmpty else { return boxTilt(boxes) > tiltMax ? nil : boxes }
        angles.sort()
        let t: Double = angles[angles.count / 2]
        if t == 0 { return boxTilt(boxes) > tiltMax ? nil : boxes }
        if abs(t) > Double.pi / 4 { return nil }
        let cs: Double = cos(t)
        let sn: Double = sin(t)
        var out: [UtilityOCRBox] = []
        for b in boxes {
            let cx: Double = (b.minX + b.maxX) / 2
            let cy: Double = (b.minY + b.maxY) / 2
            let x: Double = cx * cs + cy * sn
            let y: Double = cy * cs - cx * sn
            let quad: Bool = b.dirX != 0 || b.dirY != 0
            let w: Double = quad ? (b.dirX * b.dirX + b.dirY * b.dirY).squareRoot() : b.maxX - b.minX
            let h: Double = quad ? (b.upX * b.upX + b.upY * b.upY).squareRoot() : b.maxY - b.minY
            out.append(UtilityOCRBox(text: b.text, minX: x - w / 2, minY: y - h / 2, maxX: x + w / 2, maxY: y + h / 2))
        }
        return out
    }

    /// [final skew] 看不出斜度（沒有角、或四個角就是水平的外接矩形）時：斜 θ 拍的字塊，外接矩形的高 ≈ 字高＋寬 × sin θ。
    /// 兩塊一組（寬差 ≥ tiltMinWidthGap）算「高差 ÷ 寬差」取中位數（不到 5 組 → 0）
    static func boxTilt(_ boxes: [UtilityOCRBox]) -> Double {
        var ws: [Double] = []
        var hs: [Double] = []
        for b in boxes where !b.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let w: Double = b.maxX - b.minX
            let h: Double = b.maxY - b.minY
            if w > 0 && h > 0 {
                ws.append(w)
                hs.append(h)
            }
        }
        var slopes: [Double] = []
        for i in ws.indices {
            for j in ws.indices where j > i {
                let dw: Double = ws[j] - ws[i]
                if abs(dw) >= tiltMinWidthGap { slopes.append((hs[j] - hs[i]) / dw) }
            }
        }
        guard slopes.count >= 5 else { return 0 }
        slopes.sort()
        return slopes[slopes.count / 2]
    }

    /// 一張照片的字塊 → 讀到的值（rows → parse）。[final skew] 有字卻排不成行（斜太多）→ 什麼都不填，
    /// 而且 mayHaveAmount（不知道這張上面的金額是多少，不拿別張收據的金額來補）
    static func reading(boxes: [UtilityOCRBox], paidOn: Date, type: UtilityType) -> UtilityBillReading {
        let lines: [String] = rows(from: boxes)
        var r: UtilityBillReading = parse(lines: lines, paidOn: paidOn, type: type)
        if lines.isEmpty {
            for b in boxes where !b.text.trimmingCharacters(in: .whitespaces).isEmpty { r.mayHaveAmount = true }
        }
        return r
    }

    private static func rowText(_ g: [(index: Int, box: UtilityOCRBox)]) -> String {
        let sorted = g.sorted { a, b in
            if a.box.minX != b.box.minX { return a.box.minX < b.box.minX }
            return a.index < b.index
        }
        var parts: [String] = []
        for item in sorted {
            parts.append(item.box.text)
        }
        return parts.joined(separator: " ")
    }

    // MARK: 正規化

    /// 全形 → 半形、各種波浪號和破折號 → 「~」「-」、中文字中間的空白拿掉、
    /// 數字旁邊的 O／o → 0、l／I／| → 1（一直換到不再變；只換旁邊是數字的）。
    /// [review parse-5] l／I／| 只在「有日期記號的那一段」（空白隔開；有 / - ~ 年 月、或兩個以上的 .）或兩邊都是數字時才換；
    /// 其他地方不換（numbers 不收貼著 l／I 的數字：可能是框線也可能是 1，不猜）。
    /// [final C1] 數字頭尾的 | 也不換成空白了（「|09|」可能是 109、「7|」可能是 71）：留著，numbers 不收貼著 | 的數字
    static func normalize(_ s: String) -> String {
        var view = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v: UInt32 = u.value
            if v >= 0xFF01 && v <= 0xFF5E, let m = Unicode.Scalar(v - 0xFEE0) {
                view.append(m)
            } else if v == 0x3000 || v == 0x09 {
                view.append(" ")
            } else if v == 0x301C || v == 0x223C {
                view.append("~")
            } else if (v >= 0x2010 && v <= 0x2014) || v == 0x2212 {
                view.append("-")
            } else {
                view.append(u)
            }
        }
        let mapped: [Character] = Array(String(view))
        var chars: [Character] = dropSpacesBetweenWide(mapped)
        let dateish: [Bool] = dateishMask(chars)
        var changed = true
        var passes = 0
        while changed && passes < 8 {
            changed = false
            passes += 1
            for i in chars.indices {
                guard let to = lookalike(chars[i]) else { continue }
                let prevDigit: Bool = i > 0 && digit(chars[i - 1]) != nil
                let nextDigit: Bool = i + 1 < chars.count && digit(chars[i + 1]) != nil
                guard prevDigit || nextDigit else { continue }
                guard to == "0" || dateish[i] || (prevDigit && nextDigit) else { continue }
                chars[i] = to
                changed = true
            }
        }
        return String(chars)
    }

    /// [review parse-5] 每個字是不是在「有日期記號的那一段」裡（空白隔開；段裡有 / - ~ 年 月，或兩個以上的 .）
    private static func dateishMask(_ c: [Character]) -> [Bool] {
        var out: [Bool] = Array(repeating: false, count: c.count)
        var i = 0
        while i < c.count {
            if c[i] == " " {
                i += 1
                continue
            }
            var j = i
            var marks = false
            var dots = 0
            while j < c.count && c[j] != " " {
                let ch: Character = c[j]
                if ch == "/" || ch == "-" || ch == "~" || ch == "年" || ch == "月" { marks = true }
                if ch == "." { dots += 1 }
                j += 1
            }
            if marks || dots >= 2 {
                for k in i..<j { out[k] = true }
            }
            i = j
        }
        return out
    }

    /// [harden-3] 英文字母（沒換掉的 l／I 也是；貼著數字的話那個數字不收）
    private static func isLatinLetter(_ ch: Character) -> Bool {
        guard let a = ch.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    /// [harden-3] i 起是「kWh」（大小寫都算）、後面不再接英文字母：度數的單位，不算壞字
    private static func kwhUnitAt(_ c: [Character], _ i: Int) -> Bool {
        guard i + 3 <= c.count else { return false }
        let w: String = String(c[i..<(i + 3)]).lowercased()
        return w == "kwh" && (i + 3 == c.count || !isLatinLetter(c[i + 3]))
    }

    /// 「計 費 度 數」→「計費度數」：一段空白兩邊都是非 ASCII 的字（中文）才拿掉
    private static func dropSpacesBetweenWide(_ c: [Character]) -> [Character] {
        var out: [Character] = []
        var i = 0
        while i < c.count {
            if c[i] == " " {
                var j = i
                while j < c.count && c[j] == " " { j += 1 }
                let wideBefore: Bool = i > 0 && !c[i - 1].isASCII
                let wideAfter: Bool = j < c.count && !c[j].isASCII
                if !(wideBefore && wideAfter) {
                    for _ in i..<j { out.append(" ") }
                }
                i = j
            } else {
                out.append(c[i])
                i += 1
            }
        }
        return out
    }

    private static func lookalike(_ c: Character) -> Character? {
        switch c {
        case "O", "o": return "0"
        case "l", "I", "|": return "1"
        default: return nil
        }
    }

    static func digit(_ c: Character) -> Int? {
        guard let a = c.asciiValue, a >= 48, a <= 57 else { return nil }
        return Int(a) - 48
    }

    // MARK: 一行裡的日期、數字、標籤

    struct DateHit: Equatable {
        let key: String
        let start: Int
        let end: Int
    }

    struct NumberHit: Equatable {
        let value: Double
        let start: Int
        let end: Int
    }

    enum Field: Equatable {
        case usage, currentIndex, previousIndex, amount, period, readDate, previousReadDate

        var isDate: Bool { self == .period || self == .readDate || self == .previousReadDate }
    }

    struct Word {
        let chars: [Character]
        let field: Field
        let priority: Int
    }

    struct LabelHit: Equatable {
        let field: Field
        let priority: Int
        let start: Int
        let end: Int
    }

    struct Line {
        let chars: [Character]
        let labels: [LabelHit]
        let dates: [DateHit]
        let numbers: [NumberHit]
        /// [final C1] 壞掉、不收的數字的開頭位置
        let bad: [Int]
    }

    struct Candidate {
        let field: Field
        let priority: Int
        let number: Double?
        let dates: [String]
    }

    /// 這一行裡所有的日期：民國年 3 位數（100–199）+1911、西元 4 位數（2000–2199）；
    /// 「115/07/13」「115.07.13」「115-07-13」「115年07月13日」（中間可以有空白）；月、日要是真的那一天。
    /// [final B1] 日期被讀壞的不收、也不取前段：前面貼著英文字母、後面緊接英文字母／數字／? 這種（「115/09/1B」不是 9/1）、
    /// 日是一位數又隔一個空白接一兩位數（「115/09/1 1」）；「年」式一定要有「日」（「115年9月1 1日」）
    static func dates(in c: [Character]) -> [DateHit] {
        var out: [DateHit] = []
        var i = 0
        while i < c.count {
            if let hit = dateAt(c, i) {
                out.append(hit)
                i = hit.end
            } else {
                i += 1
            }
        }
        return out
    }

    private static func dateAt(_ c: [Character], _ i: Int) -> DateHit? {
        if i > 0 && (digit(c[i - 1]) != nil || isLatinLetter(c[i - 1])) { return nil }
        guard let yr = readDigits(c, i, maxDigits: 4) else { return nil }
        let yearLen: Int = yr.end - i
        let y: Int
        if yearLen == 3 && yr.value >= 100 && yr.value <= 199 {
            y = yr.value + 1911
        } else if yearLen == 4 && yr.value >= 2000 && yr.value <= 2199 {
            y = yr.value
        } else {
            return nil
        }
        var j: Int = skipSpaces(c, yr.end)
        guard j < c.count else { return nil }
        let sep1: Character = c[j]
        let sep2: Character
        switch sep1 {
        case "/", ".", "-": sep2 = sep1
        case "年": sep2 = "月"
        default: return nil
        }
        j = skipSpaces(c, j + 1)
        guard let mo = readDigits(c, j, maxDigits: 2) else { return nil }
        j = skipSpaces(c, mo.end)
        guard j < c.count, c[j] == sep2 else { return nil }
        j = skipSpaces(c, j + 1)
        let dayAt: Int = j
        guard let dd = readDigits(c, j, maxDigits: 2) else { return nil }
        j = dd.end
        if sep1 == "年" {
            let k: Int = skipSpaces(c, j)
            guard k < c.count, c[k] == "日" else { return nil }
            j = k + 1
        } else if !dateTailOK(c, j, oneDigitDay: dd.end - dayAt == 1) {
            return nil
        }
        guard mo.value >= 1, mo.value <= 12, dd.value >= 1, dd.value <= daysIn(year: y, month: mo.value) else { return nil }
        let key = String(format: "%04ld-%02ld-%02ld", y, mo.value, dd.value)
        return DateHit(key: key, start: i, end: j)
    }

    /// [final B1] 日期後面可以接的英數符號（空白、中文字、行尾也可以）
    private static let dateTailMarks: Set<Character> = ["~", "-", "(", ")", "[", "]", ","]

    /// [final B1] 「/」「.」「-」式的日期最後一位後面：緊接英文字母、數字、其他符號（「1B」「1?」）→ 讀壞了；
    /// 日是一位數、隔空白又接一兩位數或英文字母（「1 1」「1 g」）→ 也是讀壞了
    private static func dateTailOK(_ c: [Character], _ j: Int, oneDigitDay: Bool) -> Bool {
        guard j < c.count else { return true }
        let ch: Character = c[j]
        if ch.isASCII && ch != " " && !dateTailMarks.contains(ch) { return false }
        if oneDigitDay {
            let k: Int = skipSpaces(c, j)
            if k > j && k < c.count && (readDigits(c, k, maxDigits: 2) != nil || isLatinLetter(c[k])) { return false }
        }
        return true
    }

    /// 從 i 起連續的數字（1…maxDigits 位；多一位就不算）
    private static func readDigits(_ c: [Character], _ i: Int, maxDigits: Int) -> (value: Int, end: Int)? {
        var j = i
        var v = 0
        while j < c.count, let d = digit(c[j]) {
            if j - i >= maxDigits { return nil }
            v = v * 10 + d
            j += 1
        }
        return j > i ? (value: v, end: j) : nil
    }

    private static func skipSpaces(_ c: [Character], _ i: Int) -> Int {
        var j = i
        while j < c.count && c[j] == " " { j += 1 }
        return j
    }

    static func daysIn(year y: Int, month m: Int) -> Int {
        switch m {
        case 2:
            let leap: Bool = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    /// 這一行裡的數字（日期那幾段不算）：「1,590」「702,640」去千分位；「21-40-0218-50-1」（電號）、「10:30」、「115/07」這種不算；
    /// [harden-3] 逗號後面不是剛好 3 位數（「1,59」「1,5900」）、貼著英文字母（「7B2」「S02」「1,5B0」；後面接 kWh 不算）→ 整個不收，不取前段
    static func numbers(in c: [Character], skipping dates: [DateHit]) -> [NumberHit] {
        numberScan(c, dates).hits
    }

    /// [final C1] 數字＋壞掉的數字（不收的那幾個的開頭位置）：同一段有壞掉的數字 → candidates 整段不填（不拿下一個數字）
    private static func numberScan(_ c: [Character], _ dates: [DateHit]) -> (hits: [NumberHit], bad: [Int]) {
        var out: [NumberHit] = []
        var bad: [Int] = []
        var i = 0
        while i < c.count {
            if let d = dateCovering(dates, i) {
                i = d.end
                continue
            }
            guard digit(c[i]) != nil else {
                i += 1
                continue
            }
            var j = i
            while j < c.count && isNumberChar(c[j]) && dateCovering(dates, j) == nil {
                j += 1
            }
            // [review parse-5][harden-3][final C1] 頭尾貼著壞字 → 不收
            if brokenEdge(c, i, j) {
                bad.append(i)
            } else if let hits = numberTokens(c, i, j) {
                out += hits
            } else {
                bad.append(i)
            }
            i = j
        }
        return (hits: out, bad: bad)
    }

    /// [final C1] 數字頭尾的壞字：「;」「'」「|」（千分位、1 被讀壞，或框線）
    private static let glueMarks: Set<Character> = [";", "'", "|"]

    /// [harden-3][final C1] i..<j 這個數字的頭尾貼著壞字：英文字母（後面接 kWh 不算）、; ' |；前面貼著逗號、小數點（「I,590」的 590、「|.004」）；
    /// 尾巴是逗號、跳過空白又接數字（「1, 590」的 1）
    private static func brokenEdge(_ c: [Character], _ i: Int, _ j: Int) -> Bool {
        if i > 0 {
            let p: Character = c[i - 1]
            if p == "," || p == "." || isLatinLetter(p) || glueMarks.contains(p) { return true }
        }
        var end: Int = j
        while end > i && digit(c[end - 1]) == nil { end -= 1 }
        if c[end..<j].contains(",") {
            let k: Int = skipSpaces(c, j)
            if k < c.count && digit(c[k]) != nil { return true }
        }
        guard j < c.count else { return false }
        if isLatinLetter(c[j]) { return !kwhUnitAt(c, j) }
        return glueMarks.contains(c[j])
    }

    private static func dateCovering(_ dates: [DateHit], _ i: Int) -> DateHit? {
        for d in dates where d.start <= i && i < d.end { return d }
        return nil
    }

    private static func isNumberChar(_ ch: Character) -> Bool {
        digit(ch) != nil || ch == "," || ch == "." || ch == "-" || ch == "/" || ch == ":"
    }

    /// 一段數字字元 → 數字；[] ＝不是數字（電號、時間、半個日期），nil ＝壞掉的數字（[final C1] 記成 bad）
    private static func numberTokens(_ c: [Character], _ a: Int, _ b: Int) -> [NumberHit]? {
        var end = b
        while end > a && digit(c[end - 1]) == nil { end -= 1 }
        guard end > a else { return [] }
        let run: [Character] = Array(c[a..<end])
        if run.contains("/") || run.contains(":") || run.contains("-") { return [] }
        var parts: [[Character]] = []
        var cur: [Character] = []
        for ch in run {
            if ch == "," {
                parts.append(cur)
                cur = []
            } else {
                cur.append(ch)
            }
        }
        parts.append(cur)
        if parts.count > 1 {
            // [harden-3] 不是千分位的逗號（「1,59」「1,5900」）：多半是壞字截斷 → 整個不收
            guard thousands(parts) else { return nil }
            var joined: [Character] = []
            for p in parts { joined += p }
            guard let v = plainNumber(joined) else { return nil }
            return [NumberHit(value: v, start: a, end: end)]
        }
        guard let v = plainNumber(run) else { return nil }
        return [NumberHit(value: v, start: a, end: end)]
    }

    /// 「1,590」「12,342.5」：第一段 1–3 位、後面每段小數點前剛好 3 位、只有最後一段可以有小數點
    private static func thousands(_ parts: [[Character]]) -> Bool {
        guard parts.count > 1, let first = parts.first, first.count >= 1, first.count <= 3, !first.contains(".") else { return false }
        for k in 1..<parts.count {
            let p: [Character] = parts[k]
            var intLen = 0
            for ch in p {
                if ch == "." { break }
                intLen += 1
            }
            if intLen != 3 { return false }
            if k < parts.count - 1 && p.contains(".") { return false }
        }
        return true
    }

    /// 只有數字和最多一個小數點、頭尾都是數字
    private static func plainNumber(_ p: [Character]) -> Double? {
        guard let f = p.first, let l = p.last, digit(f) != nil, digit(l) != nil else { return nil }
        var dots = 0
        for ch in p {
            if ch == "." {
                dots += 1
            } else if digit(ch) == nil {
                return nil
            }
        }
        guard dots <= 1, let v = Double(String(p)), v.isFinite else { return nil }
        return v
    }

    /// 這一種帳單認得的標籤（同一個位置有好幾個對得上：取最長的）。priority 小的優先
    static func words(for t: UtilityType) -> [Word] {
        var out: [Word] = []
        func add(_ list: [String], _ field: Field, _ priority: Int) {
            for w in list {
                out.append(Word(chars: Array(w), field: field, priority: priority))
            }
        }
        add(["計費度數"], .usage, 0)
        add(["本期度數", "實用度數", "使用度數"], .usage, 1)
        switch t {
        case .electricity: add(["用電度數", "本期用電度數"], .usage, 1)
        case .water: add(["用水度數", "本期用水度數"], .usage, 1)
        case .gas: add(["用氣度數", "本期用氣度數"], .usage, 1)
        }
        add(["本期指數", "本次指數", "本期抄表指數", "本次抄表指數", "本期指針", "本次指針", "本期讀數", "本次讀數"], .currentIndex, 0)
        add(["上期指數", "上次指數", "上期抄表指數", "上次抄表指數", "上期指針", "上次指針", "上期讀數", "上次讀數"], .previousIndex, 0)
        add(["應繳總金額", "本期應繳總金額", "應繳總額"], .amount, 0)
        add(["本期應繳金額", "應繳金額", "本期應繳"], .amount, 1)
        add(["繳費金額"], .amount, 2)
        add(["計費期間", "用電期間", "用水期間", "用氣期間", "使用期間", "抄表期間", "計費起訖", "計費起迄", "計費日期"], .period, 0)
        add(["本次抄表日", "本期抄表日", "本次抄表日期", "本期抄表日期", "抄表日期", "抄表日"], .readDate, 0)
        add(["上次抄表日", "上期抄表日", "上次抄表日期", "上期抄表日期"], .previousReadDate, 0)
        return out
    }

    static func labels(in c: [Character], words: [Word]) -> [LabelHit] {
        var out: [LabelHit] = []
        var i = 0
        while i < c.count {
            var best: Word? = nil
            for w in words where matches(c, i, w.chars) {
                if let b = best, b.chars.count >= w.chars.count { continue }
                best = w
            }
            if let b = best {
                // [review parse-3] 「抄表日數 61」「抄表日天數」不是抄表日
                let after: Int = i + b.chars.count
                if (b.field == .readDate || b.field == .previousReadDate) && after < c.count && (c[after] == "數" || c[after] == "天") {
                    i += 1
                    continue
                }
                out.append(LabelHit(field: b.field, priority: b.priority, start: i, end: i + b.chars.count))
                i += b.chars.count
            } else {
                i += 1
            }
        }
        return out
    }

    private static func matches(_ c: [Character], _ i: Int, _ w: [Character]) -> Bool {
        guard !w.isEmpty, i + w.count <= c.count else { return false }
        for k in 0..<w.count where c[i + k] != w[k] { return false }
        return true
    }

    private static func hasDistractor(_ c: [Character], _ a: Int, _ b: Int) -> Bool {
        guard a < b, a >= 0, b <= c.count else { return false }
        let s = String(c[a..<b])
        for w in distractors where s.contains(w) { return true }
        return false
    }

    /// [harden-4] 整行有沒有這幾個字其中一個
    private static func containsAny(_ c: [Character], _ list: [String]) -> Bool {
        let s = String(c)
        for w in list where s.contains(w) { return true }
        return false
    }

    static func scan(_ text: String, words: [Word]) -> Line {
        let c: [Character] = Array(text)
        let ds: [DateHit] = dates(in: c)
        let ns: (hits: [NumberHit], bad: [Int]) = numberScan(c, ds)
        return Line(chars: c, labels: labels(in: c, words: words), dates: ds, numbers: ns.hits, bad: ns.bad)
    }

    // MARK: 照片是哪一種帳單

    static func typeWords(_ t: UtilityType) -> [String] {
        switch t {
        case .electricity: return ["台灣電力", "台電", "電費", "電號", "用電"]
        case .water: return ["自來水", "水費", "水號", "用水"]
        case .gas: return ["天然氣", "瓦斯", "用氣", "燃氣"]
        }
    }

    /// 字數最多的那一種，而且比第二多的兩倍還多；都沒有、分不出來 nil（認不出來就照表單選的讀）
    static func detectType(_ lines: [String]) -> UtilityType? {
        let c: [Character] = Array(lines.joined(separator: "\n"))
        var bestType: UtilityType? = nil
        var best = 0
        var second = 0
        for t in [UtilityType.electricity, .water, .gas] {
            var n = 0
            for w in typeWords(t) {
                n += occurrences(Array(w), in: c)
            }
            if n > best {
                second = best
                best = n
                bestType = t
            } else if n > second {
                second = n
            }
        }
        guard let bt = bestType, best > 2 * second else { return nil }
        return bt
    }

    private static func occurrences(_ w: [Character], in c: [Character]) -> Int {
        var n = 0
        var i = 0
        while i + w.count <= c.count {
            if matches(c, i, w) {
                n += 1
                i += w.count
            } else {
                i += 1
            }
        }
        return n
    }

    // MARK: 標籤 → 候選值

    /// 每一行每個標籤：同一行標籤後面（到下一個標籤前）第一個數字／日期；這一行沒有 → 下一行（下一行不能有標籤、不能有「去年」這些字）。
    /// 一行好幾個標籤都沒值、下一行數字一樣多 → 照順序一對一（表頭一行、數字一行那種）
    static func candidates(_ lines: [Line]) -> [Candidate] {
        var out: [Candidate] = []
        // [review parse-1] 哪幾行的數字被上一行的標籤借走了
        var lent: [Bool] = Array(repeating: false, count: lines.count)
        for li in lines.indices {
            let ln: Line = lines[li]
            var pending: [LabelHit] = []
            for k in ln.labels.indices {
                let l: LabelHit = ln.labels[k]
                let from: Int = k == 0 ? 0 : ln.labels[k - 1].end
                let segEnd: Int = k + 1 < ln.labels.count ? ln.labels[k + 1].start : ln.chars.count
                if hasDistractor(ln.chars, from, l.start) { continue }
                if l.field.isDate {
                    if let c = dateCandidate(lines, li, l, segEnd) { out.append(c) }
                    continue
                }
                // [final C1] 這一段有壞掉的數字（「I,590」「10,05 8」「1;590」）→ 整段不填，不拿下一個數字、也不往下借
                if hasBad(ln, l.end, segEnd) { continue }
                var firstAt: Int? = nil
                for (ni, n) in ln.numbers.enumerated() where n.start >= l.end && n.end <= segEnd {
                    firstAt = ni
                    break
                }
                if let ni = firstAt {
                    let n: NumberHit = ln.numbers[ni]
                    if hasDistractor(ln.chars, l.end, n.start) { continue }
                    let got: (value: Double?, last: Int) = pickNumber(ln, ni, l.field, from: l.end, end: segEnd, joinSpaces: true)
                    out.append(Candidate(field: l.field, priority: l.priority, number: got.value, dates: []))
                } else if !hasDistractor(ln.chars, l.end, segEnd) {
                    pending.append(l)
                }
            }
            guard !pending.isEmpty, li + 1 < lines.count else { continue }
            let nx: Line = lines[li + 1]
            guard nx.labels.isEmpty, nx.bad.isEmpty, !hasDistractor(nx.chars, 0, nx.chars.count) else { continue }
            // [review parse-1][final D1] 上一行是沒被借走、像一排數字的行（「702」「702 kWh」「I 31」「起 至 訖 702」）→
            // 數字那一欄整排比標籤高半行（斜拍）：往下借會借到下一個標籤的數字，不借
            if li > 0 && !lent[li - 1] && numberColumn(lines[li - 1]) { continue }
            // [harden-2] 借的那行要是光數字的一行（開頭是「尖峰」「夏月」「用戶」這種字的不借），後面也不能緊接著同樣形狀的
            // 數字行（多列表格：時間電價、夏月／非夏月）→ 不從這個表取（指數對得上也不算；有「計費度數 702」那種總數行照用那一行）
            if !bareNumbers(nx) || tableRow(lines, li + 2, like: nx) { continue }
            // [final A1] 表頭夾了不是標籤的欄（「流動電費 應繳總金額」「基本費 計費度數」）→ 不知道數字行哪一個是哪一欄，不借
            if !headerOnly(ln, pending) { continue }
            if pending.count == nx.numbers.count {
                // 表頭一行、數字一行：照順序一對一（欄跟欄之間的空白不接）
                lent[li + 1] = true
                for (pi, l) in pending.enumerated() {
                    let from: Int = pi == 0 ? 0 : nx.numbers[pi - 1].end
                    let got: (value: Double?, last: Int) = pickNumber(nx, pi, l.field, from: from, end: nx.numbers[pi].end, joinSpaces: false)
                    out.append(Candidate(field: l.field, priority: l.priority, number: got.value, dates: []))
                }
            } else if pending.count == 1 {
                // [final A1] 只有一個標籤：數字行要剛好被這一個值用完（「120 702」不知道是哪一個）
                let l: LabelHit = pending[0]
                // [final A1] 往下借的不接空白千分位（「61 312」可能是抄表日數和金額兩欄）
                let got: (value: Double?, last: Int) = pickNumber(nx, 0, l.field, from: 0, end: nx.chars.count, joinSpaces: false)
                if got.last == nx.numbers.count - 1 {
                    lent[li + 1] = true
                    out.append(Candidate(field: l.field, priority: l.priority, number: got.value, dates: []))
                }
            }
        }
        return out
    }

    /// 一個標籤拿第 i 個數字（金額照 amountNumber、度數和指數照 meterNumber）；last＝用到第幾個數字（金額的空白千分位會多用幾個）。
    /// 拿到的數字前後不對勁 → nil（不填）：
    /// [final D2] 單位不對（金額後面接「度」「kWh」；度數、指數後面接「元」）；
    /// [final C2/D2] from 到數字中間有別的字（「計費度數 流動電費 4,298」「用電度數 g 496」「本期用電度數 NT$523」）；
    /// [final C2] 同一段（end 之前）隔空白緊接著數字、英文字母、年月日（「7 0 2」「1 702」「15 90」「43 Z kWh」「115 年」）
    private static func pickNumber(_ ln: Line, _ i: Int, _ field: Field, from: Int, end: Int,
                                   joinSpaces: Bool) -> (value: Double?, last: Int) {
        let c: [Character] = ln.chars
        let money: Bool = field == .amount
        var value: Double?
        var last: Int = i
        if money {
            let a: (value: Double, last: Int) = amountNumber(ln, i, end, joinSpaces: joinSpaces)
            value = a.value
            last = a.last
        } else {
            value = meterNumber(ln, i, field)
        }
        let k: Int = skipSpaces(c, ln.numbers[last].end)
        if k < c.count && money && (c[k] == "度" || kwhUnitAt(c, k)) { value = nil }
        if k < c.count && !money && c[k] == "元" { value = nil }
        if !gapOK(c, from, ln.numbers[i].start, money: money) { value = nil }
        if k < end && k < c.count && oddAfter(c, k) { value = nil }
        return (value: value, last: last)
    }

    /// [final C2/D2] 標籤到數字中間可以有的字（金額另外可以有 NT$、$、新臺幣；kWh 也可以）
    private static let gapChars: Set<Character> = [" ", ":", "(", ")", "度", "元", "本", "期"]
    private static let moneyGapChars: Set<Character> = ["$", "新", "台", "臺", "幣"]

    private static func gapOK(_ c: [Character], _ a: Int, _ b: Int, money: Bool) -> Bool {
        var i: Int = a
        while i < b {
            let ch: Character = c[i]
            if gapChars.contains(ch) || (money && moneyGapChars.contains(ch)) {
                i += 1
            } else if money && ch == "N" && i + 1 < b && c[i + 1] == "T" {
                i += 2
            } else if kwhUnitAt(c, i) {
                i += 3
            } else {
                return false
            }
        }
        return true
    }

    /// [final C2] 數字後面（跳過空白）是數字、年月日、英文字母（kWh 不算）→ 不對勁
    private static let dateWords: Set<Character> = ["年", "月", "日"]

    private static func oddAfter(_ c: [Character], _ k: Int) -> Bool {
        let ch: Character = c[k]
        if digit(ch) != nil || dateWords.contains(ch) { return true }
        return isLatinLetter(ch) && !kwhUnitAt(c, k)
    }

    /// [final C1] a..<b 裡有壞掉的數字
    private static func hasBad(_ ln: Line, _ a: Int, _ b: Int) -> Bool {
        for p in ln.bad where p >= a && p < b { return true }
        return false
    }

    /// [review parse-1] 光數字的一行（沒有標籤；只有數字、, . 空白、度、元、NT$、[final D1] kWh）
    private static let bareChars: Set<Character> = [",", ".", " ", "度", "元", "N", "T", "$"]

    private static func bareNumbers(_ ln: Line) -> Bool {
        guard ln.labels.isEmpty, !ln.numbers.isEmpty else { return false }
        var i = 0
        while i < ln.chars.count {
            if digit(ln.chars[i]) != nil || bareChars.contains(ln.chars[i]) {
                i += 1
            } else if kwhUnitAt(ln.chars, i) {
                i += 3
            } else {
                return false
            }
        }
        return true
    }

    /// [final D1] 像一排數字的行：沒有標籤、有數字（壞掉的也算）；除了日期只有數字、英文字母、這幾個符號
    private static let columnChars: Set<Character> = [",", ".", " ", "度", "元", "$", "~", "-", "至", "到", "/", ":", "(", ")", ";", "'", "|"]

    private static func numberColumn(_ ln: Line) -> Bool {
        guard ln.labels.isEmpty, !ln.numbers.isEmpty || !ln.bad.isEmpty else { return false }
        for (i, ch) in ln.chars.enumerated() where digit(ch) == nil && dateCovering(ln.dates, i) == nil {
            if !columnChars.contains(ch) && !isLatinLetter(ch) { return false }
        }
        return true
    }

    /// [final A1] 表頭只能有標籤和這幾個字（空白、冒號、括號、單位）
    private static let headerChars: Set<Character> = [" ", ":", "(", ")", "度", "元"]

    /// [final A1] 表頭那一行：第一個標籤前面、每個等著往下借的標籤後面（到下一個標籤），只有 headerChars
    private static func headerOnly(_ ln: Line, _ pending: [LabelHit]) -> Bool {
        guard let first = ln.labels.first, headerFill(ln.chars, 0, first.start) else { return false }
        for l in pending {
            var segEnd: Int = ln.chars.count
            for m in ln.labels where m.start >= l.end {
                segEnd = m.start
                break
            }
            if !headerFill(ln.chars, l.end, segEnd) { return false }
        }
        return true
    }

    private static func headerFill(_ c: [Character], _ a: Int, _ b: Int) -> Bool {
        guard a < b else { return true }
        for ch in c[a..<b] where !headerChars.contains(ch) { return false }
        return true
    }

    /// [harden-2] 第 k 行跟數字行同樣形狀（沒有標籤、數字一樣多）→ 多列表格的下一列。
    /// [final A1] 第 k 行也像一排數字（numberColumn；數字個數不一樣、讀壞了也算：「61」下面還有「1 408」）→ 一樣當成表格，不借
    private static func tableRow(_ lines: [Line], _ k: Int, like nx: Line) -> Bool {
        guard k < lines.count else { return false }
        let ln: Line = lines[k]
        guard ln.labels.isEmpty else { return false }
        if !ln.numbers.isEmpty && ln.numbers.count == nx.numbers.count { return true }
        return numberColumn(ln)
    }

    /// [review parse-6] 度數：「1.936」（1–3 位、小數點、剛好 3 位）多半是千分位被讀成小數點，分不出來 → nil（不收、不猜）。
    /// 指數照舊（G1：指數不接；「12.342－11.640」對不上度數就不填度數）
    private static func meterNumber(_ ln: Line, _ i: Int, _ field: Field) -> Double? {
        let n: NumberHit = ln.numbers[i]
        if field == .usage && dotThousands(Array(ln.chars[n.start..<n.end])) != nil { return nil }
        return n.value
    }

    /// [v25.624 G1] 應繳金額的千分位被讀成小數點或空白：「1.590」「1 590」「12 345」→ 1590、12345。只給金額用（台幣帳單的金額
    /// 不會有 3 位小數）；空白只接「1–2 位數＋剛好一個空白＋剛好 3 位數」（「590 120」可能是兩欄，不接），接到 ≥ 1,000,000 就不收。
    /// 表頭一行、數字一行（照順序一對一）時不接空白。度數、指數一律不接（「702 640」可能是本期、去年同期兩欄）。last＝接到第幾個數字
    private static func amountNumber(_ ln: Line, _ i: Int, _ end: Int, joinSpaces: Bool) -> (value: Double, last: Int) {
        let n: NumberHit = ln.numbers[i]
        let run: [Character] = Array(ln.chars[n.start..<n.end])
        if let v = dotThousands(run) { return (value: v, last: i) }
        guard joinSpaces, run.count <= 2, allDigits(run) else { return (value: n.value, last: i) }
        var value: Double = n.value
        var prevEnd: Int = n.end
        var k: Int = i + 1
        while k < ln.numbers.count {
            let next: NumberHit = ln.numbers[k]
            guard next.start == prevEnd + 1, next.end <= end, ln.chars[prevEnd] == " " else { break }
            let group: [Character] = Array(ln.chars[next.start..<next.end])
            guard group.count == 3, allDigits(group) else { break }
            value = value * 1000 + next.value
            prevEnd = next.end
            k += 1
        }
        return (value: value, last: k - 1)
    }

    /// 「1.590」：1–3 位數、一個小數點、剛好 3 位數 → 1590；其他 nil
    private static func dotThousands(_ run: [Character]) -> Double? {
        guard let dot = run.firstIndex(of: "."), dot >= 1, dot <= 3, run.count - dot - 1 == 3 else { return nil }
        var v: Double = 0
        for (k, ch) in run.enumerated() where k != dot {
            guard let d = digit(ch) else { return nil }
            v = v * 10 + Double(d)
        }
        return v
    }

    private static func allDigits(_ p: [Character]) -> Bool {
        guard !p.isEmpty else { return false }
        for ch in p where digit(ch) == nil { return false }
        return true
    }

    /// 期間要 2 個日期、抄表日要 1 個：先拿同一行標籤後面的，不夠再往下最多 2 行補（遇到有標籤或「去年」的行就停）。
    /// [final B3] 期間的兩個日期在同一行時，中間只能有 ~ - 至 到（「115/07/13 列印日期 115/09/15」不收）；
    /// 起日在標籤這一行、訖日在下一行（折行）→ 不收（分不出下一行那個是不是列印日、出帳日）
    private static func dateCandidate(_ lines: [Line], _ li: Int, _ l: LabelHit, _ segEnd: Int) -> Candidate? {
        let ln: Line = lines[li]
        let need: Int = l.field == .period ? 2 : 1
        var inSeg: [DateHit] = []
        for d in ln.dates where d.start >= l.end && d.end <= segEnd {
            inSeg.append(d)
        }
        if let first = inSeg.first {
            if hasDistractor(ln.chars, l.end, first.start) { return nil }
            // [final B3] 標籤到第一個日期中間只能有空白、冒號、括號、「自」「民國」（「本期抄表日 列印日 115/09/12」不收）
            for ch in ln.chars[l.end..<first.start] where !dateGapChars.contains(ch) { return nil }
        } else if hasDistractor(ln.chars, l.end, segEnd) {
            return nil
        }
        var keys: [String] = []
        if need == 2 && inSeg.count >= 2 {
            guard let p = rangePair(ln, inSeg[0], inSeg[1]) else { return nil }
            keys = p
        } else if need == 2 && inSeg.count == 1 {
            return nil
        } else if let first = inSeg.first {
            keys = [first.key]
        }
        var k: Int = li + 1
        while keys.count < need && k < lines.count && k <= li + 2 {
            let nx: Line = lines[k]
            if !nx.labels.isEmpty || hasDistractor(nx.chars, 0, nx.chars.count) { break }
            // [review parse-3] 借的那行只能有日期和 ~ - 至 到（「繳費期限 115/09/25」「列印日期 …」那種不借）
            if !onlyDates(nx) { break }
            if keys.isEmpty && need == 2 && nx.dates.count >= 2 {
                guard let p = rangePair(nx, nx.dates[0], nx.dates[1]) else { return nil }
                keys = p
            } else {
                for d in nx.dates where keys.count < need {
                    keys.append(d.key)
                }
            }
            k += 1
        }
        guard keys.count == need else { return nil }
        return Candidate(field: l.field, priority: l.priority, number: nil, dates: keys)
    }

    /// [final B3] 標籤到第一個日期中間可以有的字
    private static let dateGapChars: Set<Character> = [" ", ":", "(", ")", "自", "從", "由", "民", "國"]

    /// [final B3] 同一行的兩個日期中間（去掉空白、「民國」）剛好是 ~ - 至 到 其中一個 → 起訖
    private static func rangePair(_ ln: Line, _ a: DateHit, _ b: DateHit) -> [String]? {
        let raw: String = String(ln.chars[a.end..<b.start]).replacingOccurrences(of: "民國", with: "")
        let mid: String = raw.trimmingCharacters(in: .whitespaces)
        guard mid == "~" || mid == "-" || mid == "至" || mid == "到" else { return nil }
        return [a.key, b.key]
    }

    /// [review parse-1] 數字的標籤（度數、指數、金額）後面只有日期、或日期的標籤（期間、抄表日）後面只有數字、
    /// 或一行只有數字的標籤卻哪裡都找不到數字（dangling）→ 這張照片的數字整排錯開了一行（斜拍時標籤和數字分到不同行），同一行的數字也不可信
    static func misaligned(_ lines: [Line]) -> Bool {
        for li in lines.indices {
            let ln: Line = lines[li]
            if dangling(lines, li) { return true }
            for k in ln.labels.indices {
                let l: LabelHit = ln.labels[k]
                let segEnd: Int = k + 1 < ln.labels.count ? ln.labels[k + 1].start : ln.chars.count
                var hasDate = false
                for d in ln.dates where d.start >= l.end && d.end <= segEnd { hasDate = true }
                var hasNumber = false
                for n in ln.numbers where n.start >= l.end && n.end <= segEnd { hasNumber = true }
                let wrongKind: Bool = l.field.isDate ? (hasNumber && !hasDate) : (hasDate && !hasNumber)
                if wrongKind { return true }
            }
        }
        return false
    }

    /// [review parse-1] 這一行只有度數、指數、金額的標籤（中間只有空白、冒號），自己沒有數字，下一行也借不到
    /// （沒有下一行、下一行有標籤、有「去年」這些字、沒有數字）。[final C1] 壞掉的數字也算有數字（是讀壞了，不是錯開）
    private static func dangling(_ lines: [Line], _ li: Int) -> Bool {
        let ln: Line = lines[li]
        guard !ln.labels.isEmpty, ln.numbers.isEmpty, ln.bad.isEmpty, ln.dates.isEmpty else { return false }
        var covered: [Bool] = Array(repeating: false, count: ln.chars.count)
        for l in ln.labels {
            if l.field.isDate { return false }
            for k in l.start..<l.end { covered[k] = true }
        }
        for (i, ch) in ln.chars.enumerated() where !covered[i] && ch != " " && ch != ":" { return false }
        guard li + 1 < lines.count else { return true }
        let nx: Line = lines[li + 1]
        return !nx.labels.isEmpty || (nx.numbers.isEmpty && nx.bad.isEmpty) || hasDistractor(nx.chars, 0, nx.chars.count)
    }

    /// [review parse-3] 這一行除了日期只有空白和 ~ - 至 到
    private static func onlyDates(_ ln: Line) -> Bool {
        guard !ln.dates.isEmpty else { return false }
        for (i, ch) in ln.chars.enumerated() where dateCovering(ln.dates, i) == nil {
            if ch != " " && ch != "~" && ch != "-" && ch != "至" && ch != "到" { return false }
        }
        return true
    }

    /// 沒有標籤的「115/07/13 ~ 115/09/11」那種一行（兩個日期中間只有 ~ - 至 到；整行沒有「去年」這些字；
    /// [harden-4] 也沒有「期限」「代收」「繳費」這些字。訖日 ≤ 繳費日在 parse 的 endsBy 一起擋）。
    /// [final B2] 整行只有日期（「115/05/13~115/07/12 486」那種用電紀錄的一列不算），而且整張照片只有一段（兩段以上 → 都不算）；
    /// 照片上有「紀錄」「歷史」「近期」這些字（用電紀錄表）→ 都不算
    private static func rangeLines(_ lines: [Line]) -> [[String]] {
        for ln in lines where containsAny(ln.chars, historyWords) { return [] }
        var out: [[String]] = []
        for ln in lines where ln.labels.isEmpty && ln.dates.count >= 2 && !hasDistractor(ln.chars, 0, ln.chars.count) {
            if containsAny(ln.chars, periodStopWords) || !onlyDates(ln) { continue }
            if let p = rangePair(ln, ln.dates[0], ln.dates[1]), !out.contains(p) { out.append(p) }
        }
        return out.count == 1 ? out : []
    }

    /// 同一種欄位：priority 最小的那幾個裡、不重複的值（照出現順序）。只有一個才算讀到
    private static func distinctNumbers(_ cands: [Candidate], _ field: Field, _ valid: (Double) -> Bool) -> [Double] {
        var top: Int? = nil
        for c in cands where c.field == field {
            guard let v = c.number, valid(v) else { continue }
            if let t = top, t <= c.priority { continue }
            top = c.priority
        }
        guard let t = top else { return [] }
        var out: [Double] = []
        for c in cands where c.field == field && c.priority == t {
            guard let v = c.number, valid(v) else { continue }
            if !out.contains(v) { out.append(v) }
        }
        return out
    }

    private static func distinctDates(_ cands: [Candidate], _ field: Field) -> [[String]] {
        var out: [[String]] = []
        for c in cands where c.field == field && !c.dates.isEmpty {
            if !out.contains(c.dates) { out.append(c.dates) }
        }
        return out
    }

    private static func isUsage(_ v: Double) -> Bool { UtilityReadingIndex.validUsage(v) != nil }
    private static func isMeter(_ v: Double) -> Bool { UtilityReadingIndex.validMeter(v) != nil }
    private static func isAmount(_ v: Double) -> Bool { v.isFinite && v > 0 && v < maxAmount }

    /// 期間的形狀：兩個 key 都解得開、表單那條 periodMessage 會過（到 ≥ 從、≤ 186 天）
    static func periodOK(_ s: String, _ e: String) -> Bool {
        guard let sd = UtilityDay.date(s), let ed = UtilityDay.date(e) else { return false }
        return UtilityUsageForm.periodMessage(hasPeriod: true, start: sd, end: ed) == nil
    }

    /// [review parse-3] 訖日不在繳費日之後（帳單都是期間結束後才出單、才繳；訖日比繳費日晚多半是把繳費期限借成訖日）
    static func endsBy(_ key: String, paidOn: Date) -> Bool {
        guard let d = UtilityDay.date(key) else { return false }
        return UtilityDay.days(d, paidOn) >= 0
    }

    /// 跟繳費日相差一年內（日曆日，366 天也算）
    static func inWindow(_ key: String, paidOn: Date) -> Bool {
        guard let d = UtilityDay.date(key) else { return false }
        return abs(UtilityDay.days(d, paidOn)) <= windowDays
    }

    // MARK: 一張照片的字 → 讀到的值

    static func parse(lines: [String], paidOn: Date, type: UtilityType) -> UtilityBillReading {
        var norm: [String] = []
        for l in lines {
            let n: String = normalize(l)
            if !n.trimmingCharacters(in: .whitespaces).isEmpty { norm.append(n) }
        }
        var r = UtilityBillReading()
        let photoType: UtilityType? = detectType(norm)
        if let pt = photoType, pt != type {
            r.mismatch = true
            r.hints = [mismatchText(photo: pt, chosen: type)]
            return r
        }
        let ws: [Word] = words(for: type)
        var scanned: [Line] = []
        for n in norm {
            scanned.append(scan(n, words: ws))
        }
        // [final F1] 有應繳金額的標籤（讀不到、行對不齊也算）→ pick 不拿別張的金額來補
        for ln in scanned {
            for l in ln.labels where l.field == .amount { r.mayHaveAmount = true }
        }
        // [review parse-1] 保險：行對不齊（斜拍、Vision 的角沒轉正）→ 什麼都不填（讀錯比讀不到糟）
        if misaligned(scanned) { return r }
        let cands: [Candidate] = candidates(scanned)
        var hints: [String] = []

        // 指數（只拿來核對）
        let curs: [Double] = distinctNumbers(cands, .currentIndex, isMeter)
        let prevs: [Double] = distinctNumbers(cands, .previousIndex, isMeter)
        r.currentIndex = curs.count == 1 ? curs[0] : nil
        r.previousIndex = prevs.count == 1 ? prevs[0] : nil
        var diff: Double? = nil
        if let c = r.currentIndex, let p = r.previousIndex { diff = c - p }

        // 度數
        let usages: [Double] = distinctNumbers(cands, .usage, isUsage)
        if usages.count == 1 {
            let u: Double = usages[0]
            if let d = diff {
                if d < 0 {
                    hints.append(indexBackwards)
                } else if abs(d - u) < indexTolerance {
                    r.usage = u
                } else {
                    hints.append(indexMismatchText(usage: u, current: r.currentIndex ?? 0, previous: r.previousIndex ?? 0, diff: d))
                }
            } else {
                r.usage = u
            }
        } else if usages.count > 1 {
            // 有兩個不同的度數：指數相減剛好對上其中一個就用那個，不然不填
            var hit: [Double] = []
            if let d = diff, d >= 0 {
                for u in usages where abs(d - u) < indexTolerance { hit.append(u) }
            }
            if hit.count == 1 {
                r.usage = hit[0]
            } else {
                hints.append(usageConflictText(usages[0], usages[1]))
            }
        } else if let d = diff, d >= 0, isUsage(d), let c = r.currentIndex, let p = r.previousIndex {
            hints.append(indexOnlyText(current: c, previous: p, diff: d))
        }
        // [harden-5] 看不出是哪一種帳單：水費、瓦斯費一期超過 300 度 → 不填度數、只提示（多半是拿電費單在水費那期讀）
        if photoType == nil, type != .electricity, let u = r.usage, u > unknownTypeMaxUsage {
            r.usage = nil
            hints.append(unknownTypeUsageText(u, type: type))
        }

        // 應繳金額
        let amounts: [Double] = distinctNumbers(cands, .amount, isAmount)
        if amounts.count == 1 {
            r.amount = amounts[0]
        } else if amounts.count > 1 {
            hints.append(amountConflict)
        }

        // 計費期間：標籤 → 抄表日（上次＋1 天 ～ 本次）→ 沒標籤的「起 ~ 訖」那一行
        var pairs: [[String]] = distinctDates(cands, .period)
        if pairs.isEmpty {
            let cur: [[String]] = distinctDates(cands, .readDate)
            let prev: [[String]] = distinctDates(cands, .previousReadDate)
            if cur.count == 1, prev.count == 1, let pd = UtilityDay.date(prev[0][0]) {
                pairs = [[UtilityDay.key(WealthCal.addDays(1, to: pd)), cur[0][0]]]
            }
        }
        if pairs.isEmpty {
            for p in rangeLines(scanned) where !pairs.contains(p) {
                pairs.append(p)
            }
        }
        var good: [[String]] = []
        for p in pairs where p.count == 2 && periodOK(p[0], p[1]) {
            if inWindow(p[0], paidOn: paidOn) && inWindow(p[1], paidOn: paidOn) {
                // [review parse-3] 訖日比繳費日晚 → 不收
                if endsBy(p[1], paidOn: paidOn) && !good.contains(p) { good.append(p) }
            } else {
                r.datesOutOfRange = true
            }
        }
        if good.count == 1 {
            r.startKey = good[0][0]
            r.endKey = good[0][1]
        } else if good.count > 1 {
            hints.append(periodConflict)
        }
        r.hints = hints
        // [harden-5] 看不出是哪一種帳單、又讀到度數或期間（或有提示）→ 灰字多一句請確認類型（只有金額的收據不加，照舊說沒找到）
        if photoType == nil && (r.hasUsageOrPeriod || !hints.isEmpty) { r.typeNote = unknownTypeText(type) }
        return r
    }

    // MARK: 讀到的值 → 要填哪幾欄

    /// 只填空的欄；已經有填、跟照片不一樣 → 不改，灰字寫照片上是多少；一樣 → 不動
    static func fill(_ reading: UtilityBillReading?, now: UtilityPhotoFormNow) -> UtilityPhotoFill {
        var f = UtilityPhotoFill()
        guard let r = reading else {
            f.message = noneFound
            return f
        }
        if r.mismatch {
            f.message = r.hints.isEmpty ? nil : r.hints.joined(separator: "\n")
            return f
        }
        var kept: [String] = []
        if let u = r.usage {
            if isBlank(now.usageText) {
                f.usageText = UtilityUsageForm.usageFieldText(u)
            } else if UtilityUsageForm.parseUsage(now.usageText) != .value(u) {
                kept.append(UtilityMath.usageText(u))
            }
        }
        if let s = r.startKey, let e = r.endKey, periodOK(s, e) {
            if now.periodIsEmpty {
                f.startKey = s
                f.endKey = e
            } else if now.startKey != s || now.endKey != e {
                kept.append(periodText(s, e))
            }
        }
        if let a = r.amount {
            let typed: String = now.amountText.trimmingCharacters(in: .whitespaces)
            if typed.isEmpty {
                f.amountText = UtilityUsageForm.usageFieldText(a)
            } else if Double(typed) != a {
                kept.append("NT$" + UtilityMath.usageNumber(a))
            }
        }
        var lines: [String] = []
        if r.usage == nil && r.startKey == nil {
            if r.datesOutOfRange {
                lines.append(outOfRange)
            } else if r.hints.isEmpty {
                lines.append(noneFound)
            }
        } else if r.usage == nil {
            if r.hints.isEmpty { lines.append(noUsage) }
        } else if r.startKey == nil {
            lines.append(r.datesOutOfRange ? outOfRange : noPeriod)
        }
        let filledAny: Bool = f.usageText != nil || f.startKey != nil || f.amountText != nil
        if !kept.isEmpty {
            lines.append("照片上是 " + kept.joined(separator: "、") + "，跟已經填的不一樣，沒有改，請核對")
        } else if !filledAny && r.hasAnything {
            lines.append(sameAsFilled)
        }
        lines += r.hints
        if let n = r.typeNote { lines.append(n) }
        f.message = lines.isEmpty ? nil : lines.joined(separator: "\n")
        return f
    }

    /// 欄位現在還是照片讀的那個值才標（使用者改過、清掉就不標）
    static func marks(fill: UtilityPhotoFill?, usageText: String, amountText: String, hasPeriod: Bool,
                      start: Date, end: Date) -> UtilityPhotoMarks {
        guard let f = fill else { return UtilityPhotoMarks.empty }
        let usage: Bool = f.usageText != nil && f.usageText == usageText
        let amount: Bool = f.amountText != nil && f.amountText == amountText
        var period = false
        if hasPeriod, let s = f.startKey, let e = f.endKey {
            period = UtilityDay.key(start) == s && UtilityDay.key(end) == e
        }
        return UtilityPhotoMarks(usage: usage, period: period, amount: amount)
    }

    // MARK: 灰字

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 「2026-07-13」→「7/13」
    static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return key }
        return "\(m)/\(d)"
    }

    /// 「7/13–9/11」
    static func periodText(_ s: String, _ e: String) -> String {
        shortDay(s) + "–" + shortDay(e)
    }

    static func mismatchText(photo: UtilityType, chosen: UtilityType) -> String {
        "這張看起來是\(photo.rawValue)帳單，這一期選的是\(chosen.rawValue)；類型改對再讀一次"
    }

    /// [harden-5]「照片上看不出是電費、水費還是瓦斯費，請確認上面選的是水費」
    static func unknownTypeText(_ t: UtilityType) -> String {
        unknownTypePrefix + t.rawValue
    }

    static func unknownTypeUsageText(_ u: Double, type t: UtilityType) -> String {
        "照片上的度數（\(UtilityMath.usageNumber(u))）比\(t.rawValue)一期常見的多，度數請看帳單自己填"
    }

    static func indexMismatchText(usage: Double, current: Double, previous: Double, diff: Double) -> String {
        let u: String = UtilityMath.usageNumber(usage)
        let c: String = UtilityMath.usageNumber(current)
        let p: String = UtilityMath.usageNumber(previous)
        let d: String = UtilityMath.usageNumber(diff)
        return "照片上的度數（\(u)）跟指數相減（\(c)－\(p)＝\(d)）對不起來，度數請看帳單自己填"
    }

    static func indexOnlyText(current: Double, previous: Double, diff: Double) -> String {
        let c: String = UtilityMath.usageNumber(current)
        let p: String = UtilityMath.usageNumber(previous)
        let d: String = UtilityMath.usageNumber(diff)
        return "照片上沒找到度數；本期指數 \(c)－上期指數 \(p)＝\(d)，對的話可以自己填"
    }

    static func usageConflictText(_ a: Double, _ b: Double) -> String {
        "照片上有兩個不同的度數（\(UtilityMath.usageNumber(a))、\(UtilityMath.usageNumber(b))），請自己填"
    }
}
