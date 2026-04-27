import SwiftUI

/// 手錶端「新增變動支出」主畫面。
/// 採用 TabView .verticalPage —— 使用者可上下滑動 / 旋轉錶冠在各頁切換。
/// 完整輸入欄位（對齊 iPhone 變動支出表單）：
///   1. 金額 + 幣別
///   2. 分類
///   3. 用餐成員（飲食類常用，其他類別亦可填）
///   4. 標題
///   5. 日期
///   6. 備註
///   7. 儲存
struct WatchAddExpenseView: View {
    @EnvironmentObject var store: WatchExpenseStore

    // MARK: - 表單狀態
    @State private var amountText: String = ""
    @State private var currencyCode: String = "NT$"
    @State private var category: WatchVariableCategory = .food
    @State private var diningMember: String = ""
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""

    @State private var pageIndex: Int = 0
    @State private var showSavedToast = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let currencies = ["NT$", "US$", "JPY", "EUR", "RMB", "HKD"]
    private var amountValue: Double { Double(amountText) ?? 0 }
    private var canSave: Bool { amountValue > 0 }

    var body: some View {
        TabView(selection: $pageIndex) {
            amountPage.tag(0)
            categoryPage.tag(1)
            diningMemberPage.tag(2)
            titlePage.tag(3)
            datePage.tag(4)
            notePage.tag(5)
            savePage.tag(6)
        }
        .tabViewStyle(.verticalPage)
        .alert("已儲存", isPresented: $showSavedToast) {
            Button("好") {}
        } message: {
            Text("\(category.rawValue) \(currencyCode) \(Int(amountValue))")
        }
        .alert("儲存失敗", isPresented: $showError) {
            Button("好") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Page 1：金額 + 幣別

    private var amountPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                pageHeader("金額", page: 1)

                // 幣別選擇
                Picker("幣別", selection: $currencyCode) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.navigationLink)

                // 金額顯示
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(amountText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)

                // 數字鍵盤
                numberPad
            }
            .padding(.horizontal, 4)
        }
    }

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
                                .frame(maxWidth: .infinity, minHeight: 30)
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
            guard amountText.count < 9 else { return }
            // 防止多個 0 開頭
            if amountText == "0" && key != "0" {
                amountText = key
            } else if amountText == "0" && key == "0" {
                return
            } else {
                amountText.append(key)
            }
        }
    }

    // MARK: - Page 2：分類

    private var categoryPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                pageHeader("分類", page: 2)
                ForEach(WatchVariableCategory.allCases) { cat in
                    Button {
                        category = cat
                    } label: {
                        HStack {
                            Image(systemName: cat.icon)
                                .frame(width: 22)
                            Text(cat.rawValue)
                            Spacer()
                            if category == cat {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 3：用餐成員 / 同行人

    private var diningMemberPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageHeader(category == .food ? "用餐成員" : "同行人", page: 3)

                TextField("選填", text: $diningMember)

                Text("飲食類別建議填入；其他類別可記錄同行人。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 4：標題

    private var titlePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageHeader("標題", page: 4)

                TextField(category.rawValue, text: $title)

                Text("留空則預設使用分類名稱「\(category.rawValue)」")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 5：日期

    private var datePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageHeader("日期", page: 5)

                DatePicker(
                    "日期",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button {
                    date = Date()
                } label: {
                    Label("現在", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 6：備註

    private var notePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageHeader("備註", page: 6)
                TextField("選填", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Page 7：儲存（含摘要）

    private var savePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                pageHeader("確認", page: 7)

                summaryRow("金額", value: "\(currencyCode) \(amountText.isEmpty ? "0" : amountText)")
                summaryRow("分類", value: category.rawValue)
                if !diningMember.isEmpty {
                    summaryRow(category == .food ? "成員" : "同行", value: diningMember)
                }
                summaryRow("標題", value: title.isEmpty ? category.rawValue : title)
                summaryRow("日期", value: shortDate(date))
                if !note.isEmpty {
                    summaryRow("備註", value: note)
                }

                Button(action: save) {
                    Text("儲存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canSave)
                .padding(.top, 4)

                if !canSave {
                    Text("請先輸入金額")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 共用元件

    private func pageHeader(_ title: String, page: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(page)/7")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }

    // MARK: - 儲存

    private func save() {
        let expense = WatchExpense(
            amount: amountValue,
            category: category,
            title: title.isEmpty ? nil : title,
            note: note,
            currencyCode: currencyCode,
            diningMember: diningMember.isEmpty ? nil : diningMember,
            date: date
        )
        let ok = store.add(expense)
        if ok {
            resetForm()
            showSavedToast = true
        } else {
            errorMessage = store.saveError ?? "未知錯誤"
            showError = true
        }
    }

    private func resetForm() {
        amountText = ""
        diningMember = ""
        title = ""
        note = ""
        date = Date()
        // 保留 category 與 currencyCode 不重置（多數情況下下一筆相同）
        pageIndex = 0
    }
}

#Preview {
    NavigationStack {
        WatchAddExpenseView().environmentObject(WatchExpenseStore())
    }
}
