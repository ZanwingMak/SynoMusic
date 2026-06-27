import StoreKit
import SwiftUI

/// 付费墙：展示完整功能说明、StoreKit 商品、恢复购买和兑换入口。
struct PaywallView: View {
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.dismiss) private var dismiss

    let feature: PremiumFeature

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    featureList
                    productList
                    restoreAndRedeem
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle((purchase.hasFullAccess ? "购买与订阅" : "解锁完整功能").t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".t) { dismiss() }
                }
            }
            .task { await purchase.loadProductsIfNeeded() }
            .onChange(of: purchase.hasFullAccess) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(feature.title.t)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            Text(feature.lockedMessage.t)
                .font(.body)
                .foregroundStyle(.secondary)
            Text("订阅支持 3 天免费试用；终身版为一次性购买。".t)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("包含功能".t)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(featureItems, id: \.title) { item in
                    PaywallFeatureRow(icon: item.icon, title: item.title)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        return items.filter { (item: (icon: String, title: String)) -> Bool in
            item.title != "电台" && item.title != "播客" && item.title != "本地音乐导入"
        }
    }

    @ViewBuilder
    private var productList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择方案".t)
                .font(.headline)
            if purchase.isLoadingProducts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载内购商品".t)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else if purchase.products.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("暂时没有加载到内购商品。".t)
                        .foregroundStyle(.secondary)
                    Button("重新加载".t) {
                        Task { await purchase.loadProductsIfNeeded() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                ForEach(purchase.products, id: \.id) { product in
                    productButton(for: product)
                }
            }
            if let message = purchase.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var restoreAndRedeem: some View {
        VStack(spacing: 10) {
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

    /// 生成单个内购商品按钮。
    private func productButton(for product: Product) -> some View {
        Button {
            Task { await purchase.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localProductTitle(for: product))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(localProductSubtitle(for: product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let trial = trialText(for: product) {
                        Text(trial)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer(minLength: 10)
                if purchase.isPurchasing {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(purchase.isPurchasing)
    }

    /// 返回商品的本地标题，避免 ASC 名称未配置时 UI 空洞。
    private func localProductTitle(for product: Product) -> String {
        SynoMusicProduct(rawValue: product.id)?.title.t ?? product.displayName
    }

    /// 返回商品的本地说明。
    private func localProductSubtitle(for product: Product) -> String {
        SynoMusicProduct(rawValue: product.id)?.subtitle.t ?? product.description
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

/// 付费墙内的功能说明行。
private struct PaywallFeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(title.t)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34, alignment: .leading)
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
