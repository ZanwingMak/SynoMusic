import Foundation
import StoreKit
import UIKit

/// StoreKit 本地校验错误。
private enum PurchaseError: Error {
    case failedVerification
}

/// 商业版商品定义；App Store Connect 内购商品 ID 必须与这里保持一致。
enum SynoMusicProduct: String, CaseIterable, Identifiable {
    case weekly = "app.synomusic.SynoMusic.subscription.weekly"
    case monthly = "app.synomusic.SynoMusic.subscription.monthly"
    case quarterly = "app.synomusic.SynoMusic.subscription.quarterly"
    case yearly = "app.synomusic.SynoMusic.subscription.yearly"
    case lifetime = "app.synomusic.SynoMusic.lifetime"

    var id: String { rawValue }

    /// 商品在付费墙中的固定排序。
    var sortIndex: Int {
        switch self {
        case .weekly: return 0
        case .monthly: return 1
        case .quarterly: return 2
        case .yearly: return 3
        case .lifetime: return 4
        }
    }

    /// 商品的本地展示名称；真实价格仍以 StoreKit 返回为准。
    var title: String {
        switch self {
        case .weekly: return "周订阅"
        case .monthly: return "月订阅"
        case .quarterly: return "季订阅"
        case .yearly: return "年订阅"
        case .lifetime: return "终身版"
        }
    }

    /// 商品的短说明，用于购买列表辅助用户快速区分。
    var subtitle: String {
        switch self {
        case .weekly: return "适合先短期体验完整功能"
        case .monthly: return "按月解锁完整功能"
        case .quarterly: return "按季度解锁完整功能"
        case .yearly: return "长期使用更省心"
        case .lifetime: return "一次购买，长期使用"
        }
    }
}

/// 需要购买后解锁的功能点。
enum PremiumFeature: String, Identifiable {
    case allAccess
    case appIcon
    case backgroundPlayback
    case serverProfiles
    case localPlaylists
    case playbackHistory
    case radio
    case podcasts
    case songDownloads
    case lyricEditing
    case iCloudSync
    case smartMixes
    case downloadQueue
    case lyricTools
    case systemIntegrations
    case playbackEnhancements
    case onlineMetadata
    case localImport

    var id: String { rawValue }

    /// 功能点标题，用于付费墙和锁定提示。
    var title: String {
        switch self {
        case .allAccess: return "完整功能"
        case .appIcon: return "更换 App 图标"
        case .backgroundPlayback: return "后台播放"
        case .serverProfiles: return "多个服务器配置"
        case .localPlaylists: return "更多本地歌单"
        case .playbackHistory: return "历史记录"
        case .radio: return "电台"
        case .podcasts: return "播客"
        case .songDownloads: return "歌曲下载"
        case .lyricEditing: return "歌词编辑"
        case .iCloudSync: return "iCloud 云同步"
        case .smartMixes: return "智能歌单"
        case .downloadQueue: return "下载队列"
        case .lyricTools: return "歌词工具"
        case .systemIntegrations: return "Siri 与小组件"
        case .playbackEnhancements: return "播放增强"
        case .onlineMetadata: return "在线资料工具"
        case .localImport: return "本地音乐导入"
        }
    }

    /// 被锁定时展示给用户的解释。
    var lockedMessage: String {
        switch self {
        case .allAccess:
            return "解锁完整功能后可使用全部高级能力。"
        case .appIcon:
            return "免费版暂不支持更换 App 图标。"
        case .backgroundPlayback:
            return "免费版进入后台后会自动暂停播放。"
        case .serverProfiles:
            return "免费版最多保存 1 个服务器配置。"
        case .localPlaylists:
            return "免费版最多创建 3 个本地歌单。"
        case .playbackHistory:
            return "历史记录需要解锁完整功能后使用。"
        case .radio:
            return "电台需要解锁完整功能后使用。"
        case .podcasts:
            return "播客搜索与播放需要解锁完整功能后使用。"
        case .songDownloads:
            return "歌曲下载需要解锁完整功能后使用。"
        case .lyricEditing:
            return "歌词编辑需要解锁完整功能后使用。"
        case .iCloudSync:
            return "iCloud 云同步需要解锁完整功能后使用。"
        case .smartMixes:
            return "智能歌单需要解锁完整功能后使用。"
        case .downloadQueue:
            return "下载队列需要解锁完整功能后使用。"
        case .lyricTools:
            return "歌词工具需要解锁完整功能后使用。"
        case .systemIntegrations:
            return "Siri 与小组件需要解锁完整功能后使用。"
        case .playbackEnhancements:
            return "播放增强需要解锁完整功能后使用。"
        case .onlineMetadata:
            return "在线资料工具需要解锁完整功能后使用。"
        case .localImport:
            return "本地音乐导入需要解锁完整功能后使用。"
        }
    }
}

/// 免费版限制常量，集中维护，避免各页面写散。
enum PurchaseLimits {
    static let maxFreeServerProfiles = 1
    static let maxFreeUserPlaylists = 3
}

/// StoreKit 2 购买状态：加载商品、购买、恢复购买、兑换和监听交易更新。
@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var statusMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    var hasFullAccess: Bool {
        !purchasedProductIDs.isDisjoint(with: Set(SynoMusicProduct.allCases.map(\.rawValue)))
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 启动 StoreKit 状态监听并刷新当前权益。
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        listenForTransactions()
        await refreshEntitlements()
        await loadProductsIfNeeded()
    }

    /// 按需加载 App Store Connect 中配置的内购商品。
    func loadProductsIfNeeded() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let identifiers = SynoMusicProduct.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: identifiers)
            products = fetched.sorted { lhs, rhs in
                productSortIndex(lhs.id) < productSortIndex(rhs.id)
            }
        } catch {
            statusMessage = "内购商品加载失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 购买指定商品，并在成功后刷新权益。
    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = "购买已生效".t
            case .userCancelled:
                statusMessage = nil
            case .pending:
                statusMessage = "购买正在等待处理".t
            @unknown default:
                statusMessage = "购买状态暂时无法确认".t
            }
        } catch {
            statusMessage = "购买失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 触发系统恢复购买流程，并刷新当前权益。
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = hasFullAccess ? "购买已恢复".t : "没有找到有效购买".t
        } catch {
            guard !isUserCancelled(error) else {
                statusMessage = nil
                return
            }
            statusMessage = "恢复购买失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 打开系统订阅管理面板，方便用户查看或取消订阅。
    func manageSubscriptions() async {
        guard let scene = activeWindowScene else {
            statusMessage = "订阅管理暂不可用".t
            return
        }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            guard !isUserCancelled(error) else {
                statusMessage = nil
                return
            }
            statusMessage = "打开订阅管理失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 打开 App Store 的兑换码面板。
    func redeemOfferCode() async {
        guard let scene = activeWindowScene else {
            statusMessage = "当前无法打开兑换页面".t
            return
        }
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
        } catch {
            statusMessage = "打开兑换页面失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 判断某个功能当前是否可使用。
    func canUse(_ feature: PremiumFeature) -> Bool {
        switch feature {
        case .allAccess:
            return hasFullAccess
        default:
            return hasFullAccess
        }
    }

    /// 清除一次性状态提示。
    func clearStatusMessage() {
        statusMessage = nil
    }

    /// 从当前有效权益中刷新已购买商品 ID。
    private func refreshEntitlements() async {
        var activeIDs: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: result) else { continue }
            guard SynoMusicProduct.allCases.map(\.rawValue).contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            activeIDs.insert(transaction.productID)
        }
        purchasedProductIDs = activeIDs
        hasLoadedEntitlements = true
    }

    /// 监听交易更新，确保跨设备恢复和续订状态能及时反映到 UI。
    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? await self.verifiedTransactionOnMainActor(from: result) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    /// 在主线程校验交易签名，供异步监听任务调用。
    private func verifiedTransactionOnMainActor(from result: VerificationResult<Transaction>) async throws -> Transaction {
        try verifiedTransaction(from: result)
    }

    /// 校验 StoreKit 返回的交易签名。
    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PurchaseError.failedVerification
        }
    }

    /// 返回商品定义中的固定排序下标。
    private func productSortIndex(_ productID: String) -> Int {
        SynoMusicProduct(rawValue: productID)?.sortIndex ?? Int.max
    }

    /// 判断 StoreKit 错误是否来自用户主动取消。
    private func isUserCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let storeKitError = error as? StoreKitError,
           case .userCancelled = storeKitError {
            return true
        }
        return false
    }

    /// 当前前台窗口场景，用于展示兑换码系统面板。
    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
