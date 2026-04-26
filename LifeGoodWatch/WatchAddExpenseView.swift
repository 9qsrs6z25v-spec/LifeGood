import SwiftUI

/// 手錶端「新增變動支出」主畫面。
/// 三個欄位：金額（數字鍵盤）、分類（Picker）、儲存。
struct WatchAddExpenseView: View {
    @EnvironmentObject var store: WatchExpenseStore
    @State private var amountText: String = ""
    @State private var category: WatchVariableCategory = .food
    @State private var showSavedToast = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var amountValue: Double { Double(amountText) ?? 0 }
    private var canSave: Bool { amountValue > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 金額顯示
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(amountText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                // 數字鍵盤
                numberPad

                // 分類 Picker
                Picker("分類", selection: $category) {
                    ForEach(WatchVariableCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.navigationLink)

                // 儲存按鈕
                Button(action: save) {
                    Text("儲存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canSave)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("新增支出")
        .alert("已儲存", isPresented: $showSavedToast) {
            Button("好") {}
        } message: {
            Text("\(category.rawValue) NT$ \(Int(amountValue))")
        }
        .alert("儲存失敗", isPresented: $showError) {
            Button("好") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - 數字鍵盤

    private var numberPad: some View {
        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["⌫", "0", "C"]
        ]
        return VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKey(key)
                        } label: {
                            Text(key)
                                .font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !amountText.isEmpty { amountText.removeLast() }
        case "C":
            amountText = ""
        default:
            // 防止過長 / 多個小數點
            guard amountText.count < 9 else { return }
            amountText.append(key)
        }
    }

    // MARK: - 儲存

    private func save() {
        let expense = WatchExpense(amount: amountValue, category: category)
        let ok = store.add(expense)
        if ok {
            amountText = ""
            showSavedToast = true
        } else {
            errorMessage = store.saveError ?? "未知錯誤"
            showError = true
        }
    }
}

#Preview {
    WatchAddExpenseView().environmentObject(WatchExpenseStore())
}
