import SwiftUI

// MARK: - 金額計算機標準模組
//
// 記帳時常需要「先算再填」（例：三筆發票加總、帳單除以人數）。
// 此模組在任何金額欄位旁放一顆計算機按鈕（CalcFieldButton），點開半頁計算機
// （AmountCalculatorSheet）做基本加減乘除，按「帶入金額」把計算結果寫回欄位。
//
// 用法（金額欄位旁加一顆按鈕即可）：
//   HStack {
//       TextField("金額", text: $amountText).keyboardType(.decimalPad)
//       CalcFieldButton(text: $amountText)
//   }
// 運算採先乘除後加減；除以 0 或不完整的算式不會帶入（帶入鈕反灰）。

/// 金額欄位旁的計算機按鈕：管理 sheet 與寫回，各金額欄位共用。
struct CalcFieldButton: View {
    @Binding var text: String
    /// 帶入時的主題色（跟隨所在頁面的 accent）
    var accent: Color = .orange

    @State private var showCalculator = false

    var body: some View {
        Button {
            showCalculator = true
        } label: {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .padding(6)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showCalculator) {
            AmountCalculatorSheet(initial: text, accent: accent) { result in
                text = result
            }
        }
    }
}

/// 基本加減乘除計算機（半頁 sheet）。計算結果由「帶入金額」交回呼叫端。
struct AmountCalculatorSheet: View {
    let initial: String
    var accent: Color = .orange
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 已確定的算式（交錯存放：數字、運算子、數字…）
    @State private var expression: [String] = []
    /// 輸入中的數字
    @State private var current: String = ""

    private static let ops = ["＋", "－", "×", "÷"]

    var body: some View {
        VStack(spacing: 12) {
            // 顯示區：上行算式、下行目前值／結果預覽
            VStack(alignment: .trailing, spacing: 4) {
                Text(expressionText)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(displayText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18).padding(.top, 16)

            // 按鍵區
            VStack(spacing: 8) {
                keyRow(["AC", "⌫", "÷", "×"])
                keyRow(["7", "8", "9", "－"])
                keyRow(["4", "5", "6", "＋"])
                keyRow(["1", "2", "3", "＝"])
                HStack(spacing: 8) {
                    key("0")
                    key(".")
                    applyButton
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 16)
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
        .onAppear {
            // 帶入欄位既有金額當起始值（無效或 0 則從空白開始）
            if let v = Double(initial.trimmingCharacters(in: .whitespaces)), v != 0 {
                current = Self.format(v)
            }
        }
    }

    // MARK: 顯示

    private var expressionText: String {
        expression.isEmpty ? " " : expression.joined(separator: " ")
    }

    private var displayText: String {
        if !current.isEmpty { return current }
        if let last = expression.last, Self.ops.contains(last) { return last }
        return "0"
    }

    /// 有算式時的結果預覽（= 123）；算式不完整或除以 0 時不顯示
    private var previewText: String? {
        guard !expression.isEmpty, let v = evaluate() else { return nil }
        return "= \(Self.format(v))"
    }

    // MARK: 按鍵

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(keys, id: \.self) { key($0) }
        }
    }

    private func key(_ label: String) -> some View {
        let isOp = Self.ops.contains(label) || label == "＝"
        let isFn = label == "AC" || label == "⌫"
        return Button {
            tap(label)
        } label: {
            Text(label)
                .font(.system(size: 22, weight: isOp || isFn ? .semibold : .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    isOp ? accent.opacity(0.14)
                         : (isFn ? Color(.systemGray4).opacity(0.5) : Color(.secondarySystemBackground)),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .foregroundStyle(isOp ? accent : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var applyButton: some View {
        let enabled = finalValue != nil
        return Button {
            guard let v = finalValue else { return }
            onDone(Self.format(v))
            dismiss()
        } label: {
            Text("帶入金額")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(enabled ? accent : Color(.systemGray4), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 輸入處理

    private func tap(_ label: String) {
        switch label {
        case "AC":
            expression = []; current = ""
        case "⌫":
            if !current.isEmpty { current.removeLast() }
            else if let last = expression.last {
                expression.removeLast()
                if !Self.ops.contains(last) { current = last }   // 收回數字繼續改
            }
        case ".":
            if current.isEmpty { current = "0." }
            else if !current.contains(".") { current += "." }
        case "＝":
            guard let v = evaluate() else { return }
            expression = []
            current = Self.format(v)
        case _ where Self.ops.contains(label):
            if !current.isEmpty {
                expression.append(current); current = ""
                expression.append(label)
            } else if let last = expression.last {
                if Self.ops.contains(last) { expression[expression.count - 1] = label }   // 換運算子
                else { expression.append(label) }
            } else {
                expression = ["0", label]   // 一開頭就按運算子：從 0 起算
            }
        default:   // 數字
            // 避免 "007"：目前是純 "0" 時直接取代
            if current == "0" { current = label } else { current += label }
        }
    }

    // MARK: 運算（先乘除後加減）

    /// 帶入用的最終結果：把輸入中的數字一併算進去
    private var finalValue: Double? {
        guard let v = evaluate() else { return nil }
        return v
    }

    private func evaluate() -> Double? {
        var toks = expression
        if !current.isEmpty { toks.append(current) }
        // 尾巴掛著運算子（例 "5 ＋"）：忽略最後的運算子照算
        if let last = toks.last, Self.ops.contains(last) { toks.removeLast() }
        guard !toks.isEmpty else { return nil }
        var nums: [Double] = []
        var ops: [String] = []
        for (i, t) in toks.enumerated() {
            if i % 2 == 0 {
                guard let v = Double(t) else { return nil }
                nums.append(v)
            } else {
                ops.append(t)
            }
        }
        guard nums.count == ops.count + 1 else { return nil }
        // 先乘除
        var rn: [Double] = [nums[0]]
        var ro: [String] = []
        for (i, op) in ops.enumerated() {
            let next = nums[i + 1]
            switch op {
            case "×": rn[rn.count - 1] *= next
            case "÷":
                guard next != 0 else { return nil }   // 除以 0：不帶入
                rn[rn.count - 1] /= next
            default:
                ro.append(op); rn.append(next)
            }
        }
        // 後加減
        var result = rn[0]
        for (i, op) in ro.enumerated() {
            result = (op == "＋") ? result + rn[i + 1] : result - rn[i + 1]
        }
        guard result.isFinite else { return nil }
        return result
    }

    /// 結果格式化：整數不帶小數點，小數最多兩位並去掉尾端 0（金額欄位慣例）
    static func format(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e12 { return String(format: "%.0f", v) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
