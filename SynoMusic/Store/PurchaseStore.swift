import Foundation
import StoreKit
import UIKit

/// 自愿赞助商品；全部为可重复购买的消耗型项目，不关联功能权限。
enum SynoMusicProduct: String, CaseIterable, Identifiable {
    case thanks = "app.synomusic.SynoMusic.support.099"
    case coffee = "app.synomusic.SynoMusic.support.199"
    case treat = "app.synomusic.SynoMusic.support.299"
    case generous = "app.synomusic.SynoMusic.support.599"
    case extraordinary = "app.synomusic.SynoMusic.support.999"

    var id: String { rawValue }
    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// 本地化赞助名称；金额始终使用 App Store 返回的地区价格。
    var title: String {
        switch self {
        case .thanks: return "一份心意"
        case .coffee: return "请喝咖啡"
        case .treat: return "加份甜点"
        case .generous: return "暖心支持"
        case .extraordinary: return "特别感谢"
        }
    }
}

/// StoreKit 赞助购买状态；功能始终开放，购买只表达对开发者的支持。
@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var statusMessage: String?
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    deinit { updatesTask?.cancel() }

    /// 监听待完成交易；启动时不主动加载赞助商品或影响用户使用功能。
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      SynoMusicProduct(rawValue: transaction.productID) != nil else { continue }
                await transaction.finish()
                self.statusMessage = "感谢你的赞助与支持！".t
            }
        }
    }

    /// 加载苹果后台配置的消耗型赞助商品，并按金额档位排序。
    func loadProductsIfNeeded() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        statusMessage = nil
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: SynoMusicProduct.allCases.map(\.rawValue))
            products = fetched.filter { $0.type == .consumable }.sorted {
                (SynoMusicProduct(rawValue: $0.id)?.sortIndex ?? .max)
                    < (SynoMusicProduct(rawValue: $1.id)?.sortIndex ?? .max)
            }
            if products.isEmpty { statusMessage = "暂时没有加载到赞助项目，请稍后重试。".t }
        } catch {
            statusMessage = "赞助项目加载失败，请稍后重试。".t
        }
    }

    /// 购买一次赞助；签名校验成功后完成交易，允许再次支持同一档位。
    func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing, product.type == .consumable,
              SynoMusicProduct(rawValue: product.id) != nil else { return false }
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == product.id else {
                    statusMessage = "无法验证本次购买，请联系 Apple 支持。".t
                    return false
                }
                await transaction.finish()
                statusMessage = "感谢你的赞助与支持！".t
                return true
            case .userCancelled:
                return false
            case .pending:
                statusMessage = "购买正在等待处理".t
                return false
            @unknown default:
                statusMessage = "购买状态暂时无法确认".t
                return false
            }
        } catch {
            statusMessage = "赞助未完成，请稍后重试。".t
            return false
        }
    }

    /// 保留历史订阅的管理入口，便于老用户查看或取消仍在续费的订阅。
    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError { return }
            statusMessage = "打开订阅管理失败".t
        }
    }
}
