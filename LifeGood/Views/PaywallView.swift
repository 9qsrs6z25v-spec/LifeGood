import SwiftUI
import StoreKit

// MARK: - 升級訂閱頁

struct PaywallView: View {
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var heroAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    benefits
                    productList
                    actions
                    legal
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
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

    // MARK: - Hero 區塊

    private var header: some View {
        VStack(spacing: 0) {
            ZStack {
                // 光暈底層
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.38), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 72
                        )
                    )
                    .frame(width: 148, height: 148)
                    .scaleEffect(heroAppeared ? 1.0 : 0.55)
                    .opacity(heroAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.90), value: heroAppeared)

                // 主圓球
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.85, blue: 0.58),
                                Color(red: 0.07, green: 0.52, blue: 0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.green.opacity(0.58), radius: 24, x: 0, y: 12)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                    .scaleEffect(heroAppeared ? 1.0 : 0.45)
                    .animation(.spring(response: 0.68, dampingFraction: 0.62).delay(0.10), value: heroAppeared)

                // 主圖示
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(heroAppeared ? 1.0 : 0.35)
                    .opacity(heroAppeared ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.60).delay(0.20), value: heroAppeared)
            }
            .padding(.bottom, 22)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    heroAppeared = true
                }
            }

            Text("解鎖完整人生管理")
                .font(.title2.weight(.bold))
                .padding(.bottom, 10)

            Text("免費版本可使用記帳全部功能與理財模式的股票管理。訂閱後可解鎖儲蓄險、載具、房地產、人生履歷、家庭、管理等完整體驗。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 8)
    }

    // MARK: - 功能亮點

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 0) {
            benefitRow(icon: "shield.fill",   color: .indigo, title: "儲蓄險管理",   desc: "TWD/USD 雙幣別、複利試算、期滿領回。")
            Divider().padding(.leading, 58)
            benefitRow(icon: "car.fill",      color: .blue,   title: "載具與房地產", desc: "完整資產卡、貸款與支出連動、地圖呈現。")
            Divider().padding(.leading, 58)
            benefitRow(icon: "trophy.fill",   color: .orange, title: "人生履歷",     desc: "里程碑、家庭成員、職涯與管理工具。")
            Divider().padding(.leading, 58)
            benefitRow(icon: "icloud.fill",   color: .teal,   title: "資料完全離線", desc: "資料只存在你的裝置與 iCloud，不上傳伺服器。")
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 5)
    }

    private func benefitRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // iOS Settings 風格彩色 icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: color.opacity(0.32), radius: 5, x: 0, y: 3)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(color.opacity(0.75))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - 訂閱方案

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
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.80))
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.22))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.85, blue: 0.58),
                            Color(red: 0.07, green: 0.52, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // 裝飾性高光
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 80, height: 80)
                        .offset(x: 80, y: -32)
                        .blur(radius: 10)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.green.opacity(0.42), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(subscription.purchaseInProgress)
    }

    private func fallbackProductRow(_ product: LifeGoodProduct) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("商品載入中…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
            Text(product.fallbackPriceText)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.85, blue: 0.58),
                        Color(red: 0.07, green: 0.52, blue: 0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 80, height: 80)
                    .offset(x: 80, y: -32)
                    .blur(radius: 10)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.green.opacity(0.40), radius: 14, x: 0, y: 7)
    }

    // MARK: - 操作區

    private var actions: some View {
        VStack(spacing: 10) {
            if subscription.purchaseInProgress {
                ProgressView().tint(.green)
            }
            if let err = subscription.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("還原購買") {
                Task { await subscription.restorePurchases() }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 法律條款

    private var legal: some View {
        VStack(spacing: 8) {
            Text("訂閱會於到期前 24 小時自動續訂，可隨時於 Apple ID 設定中取消。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("使用條款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("隱私政策", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                Link("管理訂閱", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 訂閱限制提示橫幅

struct PremiumBanner: View {
    @Binding var showPaywall: Bool
    @State private var shimmer = false

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
                // 升級膠囊：脈衝亮度動畫
                Text("升級")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(shimmer ? 0.38 : 0.22))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(shimmer ? 0.60 : 0.30), lineWidth: 0.75)
                    )
                    .scaleEffect(shimmer ? 1.04 : 1.0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Color.orange, Color.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    // 右側高光
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 60, height: 60)
                        .offset(x: 100, y: -20)
                        .blur(radius: 12)
                }
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
            ) {
                shimmer = true
            }
        }
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
