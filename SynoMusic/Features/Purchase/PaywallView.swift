import StoreKit
import SwiftUI

/// 付费墙：展示完整功能说明、StoreKit 商品、恢复购买、兑换入口和法律链接。
struct PaywallView: View {
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String?

    let feature: PremiumFeature

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    planTabs
                    selectedPlanCard
                    featureList
                    restoreAndRedeem
                    statusMessage
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 132)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle((purchase.hasFullAccess ? "购买与订阅" : "解锁完整功能").t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".t) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                purchaseBar
            }
            .task {
                await purchase.loadProductsIfNeeded()
                syncSelectedProduct()
            }
            .onChange(of: availableProductIDs) { _, _ in
                syncSelectedProduct()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: purchase.hasFullAccess ? "crown.fill" : "sparkles")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(feature.title.t)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.82)
            Text(feature.lockedMessage.t)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("订阅支持 3 天免费试用；终身版为一次性购买。".t)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var planTabs: some View {
        if !availableProducts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableProducts, id: \.id) { product in
                        planTab(for: product)
                    }
                }
                .padding(4)
            }
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }

    @ViewBuilder
    private var selectedPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择方案".t)
                .font(.headline)

            if purchase.isLoadingProducts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载内购商品".t)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
            } else if availableProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("暂时没有加载到内购商品。".t)
                        .foregroundStyle(.secondary)
                    Button("重新加载".t) {
                        Task {
                            await purchase.loadProductsIfNeeded()
                            syncSelectedProduct()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let product = selectedProduct {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localProductTitle(for: product))
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                            Text(localProductSubtitle(for: product))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(product.displayPrice)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.accent)
                    }

                    if let trial = trialText(for: product) {
                        Label(trial, systemImage: "clock.badge.checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }

                    Text(subscriptionNote(for: product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("包含功能".t)
                .font(.headline)
            LazyVGrid(columns: compactFeatureColumns, alignment: .leading, spacing: 8) {
                ForEach(featureItems, id: \.title) { item in
                    PaywallFeatureRow(icon: item.icon, title: item.title)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var restoreAndRedeem: some View {
        VStack(spacing: 8) {
            Button {
                Task { await purchase.manageSubscriptions() }
            } label: {
                Label("管理订阅".t, systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Task { await purchase.restorePurchases() }
            } label: {
                Label("已经购买？恢复购买".t, systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Task { await purchase.redeemOfferCode() }
            } label: {
                Label("App 兑换".t, systemImage: "giftcard")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = purchase.statusMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            Button {
                purchaseSelectedProduct()
            } label: {
                HStack(spacing: 10) {
                    if purchase.isPurchasing {
                        ProgressView()
                    }
                    Text(primaryActionTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(primaryActionDisabled)

            HStack(spacing: 12) {
                Link("服务条款".t, destination: legalTermsURL)
                Text("·")
                    .foregroundStyle(.secondary)
                Link("隐私政策".t, destination: legalPrivacyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)

            Text("订阅由 App Store 管理，可随时在 Apple 账号中取消。".t)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var compactFeatureColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 8),
            GridItem(.flexible(minimum: 120), spacing: 8)
        ]
    }

    private var featureItems: [(icon: String, title: String)] {
        let items: [(icon: String, title: String)] = [
            ("app.badge", "更换 App 图标"),
            ("play.circle", "后台播放"),
            ("server.rack", "多个服务器配置"),
            ("music.note.list", "更多本地歌单"),
            ("clock.arrow.circlepath", "历史记录"),
            ("antenna.radiowaves.left.and.right", "电台"),
            ("mic.circle.fill", "播客"),
            ("wand.and.stars", "智能歌单"),
            ("arrow.down.circle", "歌曲下载"),
            ("tray.and.arrow.down", "下载队列"),
            ("slider.horizontal.3", "播放增强"),
            ("quote.bubble", "歌词编辑"),
            ("text.badge.checkmark", "歌词工具"),
            ("globe", "在线资料工具"),
            ("square.and.arrow.down", "本地音乐导入"),
            ("icloud", "iCloud 云同步"),
            ("sparkles.rectangle.stack", "Siri 与小组件")
        ]
        guard reviewMode.isEnabled else { return items }
        return items.filter { item in
            item.title != "电台" && item.title != "播客" && item.title != "本地音乐导入"
        }
    }

    private var availableProducts: [Product] {
        purchase.products.filter { SynoMusicProduct(rawValue: $0.id) != .quarterly }
    }

    private var availableProductIDs: [String] {
        availableProducts.map(\.id)
    }

    private var selectedProduct: Product? {
        guard let selectedProductID else { return availableProducts.first }
        return availableProducts.first { $0.id == selectedProductID } ?? availableProducts.first
    }

    private var primaryActionTitle: String {
        if purchase.hasFullAccess { return "完整功能已解锁".t }
        guard let product = selectedProduct else { return "选择方案".t }
        let productKind = SynoMusicProduct(rawValue: product.id)
        let format = productKind == .lifetime ? "购买 %@".t : "订阅 %@".t
        return String(format: format, product.displayPrice)
    }

    private var primaryActionDisabled: Bool {
        purchase.isPurchasing || purchase.hasFullAccess || selectedProduct == nil
    }

    private var legalPrivacyURL: URL {
        URL(string: "https://zanwingmak.github.io/SynoMusic-OpenSource/privacy.html")!
    }

    private var legalTermsURL: URL {
        URL(string: "https://zanwingmak.github.io/SynoMusic-OpenSource/terms.html")!
    }

    /// 生成顶部档位切换按钮。
    private func planTab(for product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let title = SynoMusicProduct(rawValue: product.id)?.tabTitle.t ?? product.displayName
        return Button {
            selectedProductID = product.id
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 68)
                .frame(minHeight: 38)
                .padding(.horizontal, 8)
                .background(isSelected ? Theme.accent : Color.clear, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 同步当前选中的商品，避免商品加载完成后没有默认档位。
    private func syncSelectedProduct() {
        guard !availableProducts.isEmpty else {
            selectedProductID = nil
            return
        }
        if let selectedProductID,
           availableProducts.contains(where: { $0.id == selectedProductID }) {
            return
        }
        selectedProductID = availableProducts.first?.id
    }

    /// 购买当前顶部 Tab 选中的商品。
    private func purchaseSelectedProduct() {
        guard let selectedProduct else { return }
        Task { await purchase.purchase(selectedProduct) }
    }

    /// 返回商品的本地标题，避免 ASC 名称未配置时 UI 空洞。
    private func localProductTitle(for product: Product) -> String {
        SynoMusicProduct(rawValue: product.id)?.title.t ?? product.displayName
    }

    /// 返回商品的本地说明。
    private func localProductSubtitle(for product: Product) -> String {
        SynoMusicProduct(rawValue: product.id)?.subtitle.t ?? product.description
    }

    /// 返回所选商品的订阅或一次性购买说明。
    private func subscriptionNote(for product: Product) -> String {
        SynoMusicProduct(rawValue: product.id) == .lifetime
            ? "终身版为一次性购买。".t
            : "订阅由 App Store 管理，可随时在 Apple 账号中取消。".t
    }

    /// 从 StoreKit 订阅介绍优惠中读取试用周期。
    private func trialText(for product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return SynoMusicProduct(rawValue: product.id) == .lifetime ? nil : "可配置 3 天免费试用".t
        }
        return String(format: "%@免费试用".t, periodText(offer.period))
    }

    /// 把订阅周期转换成本地化短文本。
    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return String(format: "%d 天".t, period.value)
        case .week: return String(format: "%d 周".t, period.value)
        case .month: return String(format: "%d 个月".t, period.value)
        case .year: return String(format: "%d 年".t, period.value)
        @unknown default: return String(format: "%d 天".t, period.value)
        }
    }
}

/// 付费墙内的紧凑功能说明行。
private struct PaywallFeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(title.t)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28, alignment: .leading)
    }
}

/// 包裹需要付费解锁的页面；未解锁时直接展示付费墙。
struct PremiumFeatureGate<Content: View>: View {
    @EnvironmentObject private var purchase: PurchaseStore
    let feature: PremiumFeature
    @ViewBuilder let content: () -> Content

    var body: some View {
        if purchase.canUse(feature) {
            content()
        } else {
            PaywallView(feature: feature)
        }
    }
}
