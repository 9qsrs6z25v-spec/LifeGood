import SwiftUI

// MARK: - 卡牌稀有度

enum CardRarity {
    case common      // 0~50萬
    case uncommon    // 51~100萬
    case rare        // 101~200萬
    case legendary   // 201~1000萬

    init(price: Double) {
        let wan = price / 10000
        switch wan {
        case ..<51: self = .common
        case ..<101: self = .uncommon
        case ..<201: self = .rare
        default: self = .legendary
        }
    }

    var label: String {
        switch self {
        case .common: return "COMMON"
        case .uncommon: return "UNCOMMON"
        case .rare: return "RARE"
        case .legendary: return "LEGENDARY"
        }
    }

    var borderGradient: [Color] {
        switch self {
        case .common: return [.gray.opacity(0.4), .gray.opacity(0.2)]
        case .uncommon: return [.cyan, .blue.opacity(0.6), .cyan]
        case .rare: return [.yellow, .orange, .yellow]
        case .legendary: return [.purple, .pink, .orange, .yellow, .green, .cyan, .blue, .purple]
        }
    }

    var bgGradient: [Color] {
        switch self {
        case .common: return [Color(.systemBackground), Color(.systemGray6)]
        case .uncommon: return [Color(.systemBackground), Color.cyan.opacity(0.05)]
        case .rare: return [Color(.systemBackground), Color.orange.opacity(0.08)]
        case .legendary: return [Color.black.opacity(0.9), Color.purple.opacity(0.15), Color.black.opacity(0.9)]
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 2.5
        case .legendary: return 3
        }
    }

    var textColor: Color {
        switch self {
        case .common: return .primary
        case .uncommon: return .cyan
        case .rare: return .orange
        case .legendary: return .yellow
        }
    }

    var shadowColor: Color {
        switch self {
        case .common: return .clear
        case .uncommon: return .cyan.opacity(0.3)
        case .rare: return .orange.opacity(0.4)
        case .legendary: return .purple.opacity(0.5)
        }
    }
}

// MARK: - 售出印章

struct SoldStamp: View {
    var size: CGFloat = 18

    var body: some View {
        Text("售出")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.red)
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.red, lineWidth: size * 0.14)
            )
            .rotationEffect(.degrees(-15))
            .shadow(color: .black.opacity(0.3), radius: size * 0.18, x: size * 0.08, y: size * 0.15)
    }
}

// MARK: - 汽車檢視卡片

struct VehicleDetailView: View {
    @EnvironmentObject var store: FinanceStore
    @EnvironmentObject var expenseStore: ExpenseStore
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var rarity: CardRarity { CardRarity(price: vehicle.purchasePrice) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flashCard
                    infoSection
                    expenseSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("車輛卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                AddVehicleView(editing: vehicle)
            }
            .alert("確定要刪除這輛車嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    deleteVehicle()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後所有連結的記帳支出也會一併移除，此操作無法復原。")
            }
        }
    }

    // MARK: - 閃卡主體

    private var flashCard: some View {
        VStack(spacing: 0) {
            // 頂部稀有度標籤
            HStack {
                Text(rarity.label)
                    .font(.caption2.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(rarity.textColor)
                Spacer()
                Label(vehicle.powerType.rawValue, systemImage: vehicle.powerType.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .yellow : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // 車名 + 品牌
            VStack(spacing: 6) {
                Text(vehicle.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(rarity == .legendary ? .white : .primary)

                if !vehicle.brand.isEmpty {
                    Text(vehicle.brand)
                        .font(.subheadline)
                        .foregroundStyle(rarity == .legendary ? .white.opacity(0.7) : .secondary)
                }
            }
            .padding(.top, 16)

            // 估值（大字）
            VStack(spacing: 4) {
                Text("\(fmtWan(vehicle.currentValue))")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(rarity.textColor)
                Text("萬元")
                    .font(.subheadline)
                    .foregroundStyle(rarity == .legendary ? .white.opacity(0.6) : .secondary)
            }
            .padding(.vertical, 20)

            // 底部資訊列
            HStack {
                VStack(spacing: 2) {
                    Text("購入")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text("\(fmtWan(vehicle.purchasePrice)) 萬")
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("折舊")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.1f%%", vehicle.depreciationRate))
                        .font(.caption.bold()).foregroundStyle(.red)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("持有")
                        .font(.caption2).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.5) : Color(UIColor.tertiaryLabel))
                    Text(String(format: "%.1f 年", vehicle.yearsOwned))
                        .font(.caption.bold()).foregroundStyle(rarity == .legendary ? Color.white.opacity(0.8) : Color.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(colors: rarity.bgGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    AngularGradient(colors: rarity.borderGradient, center: .center),
                    lineWidth: rarity.borderWidth
                )
        )
        .shadow(color: rarity.shadowColor, radius: rarity == .legendary ? 15 : 8, y: 4)
        .overlay(alignment: .topLeading) {
            if vehicle.isSold {
                SoldStamp(size: 32)
                    .offset(x: -10, y: -14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - 詳細資訊

    private var infoSection: some View {
        VStack(spacing: 0) {
            if !vehicle.fixedExpenses.isEmpty {
                sectionHeader("定期支出")
                ForEach(vehicle.fixedExpenses) { fe in
                    HStack {
                        Text(fe.category.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(fe.period == .monthly ? "每月" : "每年")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(fmt(fe.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }

            if !vehicle.variableExpenses.isEmpty {
                sectionHeader("變動支出")
                ForEach(vehicle.variableExpenses) { ve in
                    HStack {
                        Text(ve.category.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                        Text(fmt(ve.amount)).font(.subheadline.bold())
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - 操作按鈕

    private var expenseSection: some View {
        VStack(spacing: 12) {
            Button {
                showEdit = true
            } label: {
                Label("編輯", systemImage: "pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Label("刪除", systemImage: "trash")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 輔助

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
    }

    private func deleteVehicle() {
        for fe in vehicle.fixedExpenses {
            if let linkedId = fe.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        for ve in vehicle.variableExpenses {
            if let linkedId = ve.linkedExpenseId {
                expenseStore.expenses.removeAll { $0.id == linkedId }
            }
        }
        store.deleteVehicle(vehicle)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencySymbol = "NT$"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "NT$0"
    }

    private func fmtWan(_ v: Double) -> String {
        String(format: "%g", v / 10000)
    }
}
