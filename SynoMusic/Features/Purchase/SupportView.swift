import StoreKit
import SwiftUI

/// 自愿赞助页：功能全部免费，赞助仅用于感谢开发者，不自动续费。
struct SupportView: View {
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showThanks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(theme.current.accent(in: colorScheme))
                        Text("感谢赞助开发".t).font(.largeTitle.bold())
                        Text("如果 SynoMusic 让你更享受自己的音乐，欢迎支持它继续成长。".t)
                            .foregroundStyle(.secondary)
                        Text("所有功能免费开放。赞助完全自愿，不解锁额外功能，也不会自动续费。".t)
                            .font(.callout)
                    }
                    if purchase.isLoadingProducts {
                        ProgressView("正在加载赞助项目".t)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(purchase.products, id: \.id) { product in
                            supportButton(product)
                        }
                        if purchase.products.isEmpty {
                            Button("重新加载".t) {
                                Task { await purchase.loadProductsIfNeeded() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if let message = purchase.statusMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Text("赞助是一次性消耗型购买，可以重复支持；不提供可恢复的功能权益。".t)
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Link("服务条款 (EULA)".t, destination: URL(string: "https://zanwingmak.github.io/SynoMusic/terms.html")!)
                        Link("隐私政策".t, destination: URL(string: "https://zanwingmak.github.io/SynoMusic/privacy.html")!)
                    }
                    .font(.footnote)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("支持开发".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成".t) { dismiss() } }
            }
            .task { await purchase.loadProductsIfNeeded() }
            .alert("感谢支持".t, isPresented: $showThanks) {
                Button("好的".t) { }
            } message: {
                Text("感谢你的赞助与支持！".t)
            }
            .interactiveDismissDisabled(purchase.isPurchasing)
        }
    }

    /// 显示真实地区价格并执行单次购买，避免重复点击产生并行购买。
    private func supportButton(_ product: Product) -> some View {
        Button {
            Task {
                if await purchase.purchase(product) {
                    Haptics.success()
                    showThanks = true
                }
            }
        } label: {
            HStack {
                Image(systemName: "heart")
                Text((SynoMusicProduct(rawValue: product.id)?.title ?? product.displayName).t)
                Spacer()
                if purchase.isPurchasing { ProgressView() }
                Text(product.displayPrice).fontWeight(.semibold)
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(purchase.isPurchasing)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }
}
