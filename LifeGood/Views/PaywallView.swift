import SwiftUI
import StoreKit

// MARK: - 升級訂閱頁

struct PaywallView: View {
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    productList
                    actions
                    legal
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("LifeGood Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .task { await subscription.loadProducts() }
        }
    }

    // MARK: - 區塊

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.green)
            Text("解鎖完整人生管理")
                .font(.title2.weight(.bold))
            Text("免費版本可使用記帳全部功能與理財模式的股票管理。訂閱後可解鎖儲蓄險、載具、房地產、人生履歷、家庭、管理等完整體驗。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow(icon: "shield.fill", title: "儲蓄險管理", desc: "TWD/USD 雙幣別、複利試算、期滿領回。")
            benefitRow(icon: "car.fill", title: "載具與房地產", desc: "完整資產卡、貸款與支出連動、地圖呈現。")
            benefitRow(icon: "trophy.fill", title: "人生履歷", desc: "里程碑、家庭成員、職涯與管理工具。")
            benefitRow(icon: "icloud.fill", title: "資料完全離線", desc: "資料只存在你的裝置與 iCloud，不上傳伺服器。")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func benefitRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var productList: some View {
        VStack(spacing: 12) {
            if subscription.products.isEmpty {
                ForEach(LifeGoodProduct.allCases, id: \.rawValue) { p in
                    fallbackProductRow(p)
                }
            } else {
                ForEach(subscription.products, id: \.id) { product in
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        Button {
            Task { await subscription.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName).font(.headline)
                    Text(product.description).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice).font(.headline.weight(.bold))
            }
            .padding(16)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(subscription.purchaseInProgress)
    }

    private func fallbackProductRow(_ product: LifeGoodProduct) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayTitle).font(.headline)
                Text("商品載入中…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.fallbackPriceText).font(.headline.weight(.bold))
        }
        .padding(16)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if subscription.purchaseInProgress {
                ProgressView()
            }
            if let err = subscription.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Button("還原購買") {
                Task { await subscription.restorePurchases() }
            }
            .font(.footnote)
        }
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("訂閱會於到期前 24 小時自動續訂，可隨時於 Apple ID 設定中取消。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Link("使用條款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("隱私政策", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                Link("管理訂閱", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            .font(.caption2)
        }
    }
}

// MARK: - 訂閱限制提示橫幅

struct PremiumBanner: View {
    @Binding var showPaywall: Bool

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                Text(FeatureGate.viewOnlyMessage)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("升級")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.orange, Color.pink],
                               startPoint: .leading, endPoint: .trailing)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 「訂閱功能僅供閱覽」彈窗修飾器

struct PremiumLockAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .alert("訂閱功能僅供閱覽", isPresented: $isPresented) {
                Button("升級訂閱") { showPaywall = true }
                Button("關閉", role: .cancel) {}
            } message: {
                Text(FeatureGate.viewOnlyDetail)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subscription)
            }
    }
}

extension View {
    /// 在頁面附加一個「訂閱功能僅供閱覽」的提示 alert 與升級彈窗。
    func premiumLockAlert(isPresented: Binding<Bool>) -> some View {
        modifier(PremiumLockAlertModifier(isPresented: isPresented))
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager.shared)
}
