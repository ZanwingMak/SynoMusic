import Foundation

/// 同一开发者已上架的作品，商店编号和平台信息随安装包提供。
struct DeveloperApp: Decodable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let platforms: [String]
    let summary: [String: String]

    /// 使用不限定地区的商店入口，由 App Store 选择用户所在商店。
    var storeURL: URL { URL(string: "https://apps.apple.com/app/id\(id)")! }

    /// 明确标识作品可用的平台，避免把电视应用误当作手机应用。
    var platformLabel: String {
        platforms.map { $0 == "iOS" ? "iPhone · iPad" : "Apple TV" }.joined(separator: " · ")
    }

    /// 简介跟随应用内语言，缺失时回退到英文。
    func description(language: String) -> String { summary[language] ?? summary["en"] ?? name }
}

/// Apple 与桌面客户端共享一份推荐目录，启动不请求远端推广配置。
struct DeveloperAppCatalog: Decodable {
    let apps: [DeveloperApp]
    let strings: [String: [String: String]]

    static let shared: DeveloperAppCatalog = {
        guard let url = Bundle.main.url(forResource: "developer-apps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(DeveloperAppCatalog.self, from: data) else {
            return DeveloperAppCatalog(apps: [], strings: [:])
        }
        return catalog
    }()

    /// 仅列出当前设备可以使用的作品，不展示尚未上架的产品。
    static var availableApps: [DeveloperApp] {
        #if os(tvOS)
        shared.apps.filter { $0.platforms.contains("tvOS") }
        #else
        shared.apps.filter { $0.platforms.contains("iOS") }
        #endif
    }
}
