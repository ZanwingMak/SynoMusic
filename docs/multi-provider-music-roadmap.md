# Jellyfin / Emby / Plex 音乐源支持路线

本文档用于约束 SynoMusic 后续多音乐源开发方向，防止项目从“Apple 原生私人音乐客户端”偏移成完整媒体服务器或视频播放器。

## 产品定位

SynoMusic 的长期定位是：

> 面向 NAS 和自建媒体库的 Apple 原生音乐客户端，支持 Synology Audio Station、Jellyfin、Emby、Plex 等音乐来源。

核心价值不是替代 Jellyfin、Emby、Plex 或 Synology 服务器，而是连接用户已有的媒体服务，并在 iPhone / iPad / Apple 生态里提供更好的音乐播放、歌词、下载、小组件、灵动岛、锁屏、iCloud 同步和本地歌单体验。

## 必须坚持的边界

- 只支持音乐，不做电影、剧集、照片、Live TV。
- 不做视频播放器，不处理字幕、HDR、杜比音轨、视频转码、章节、剧集元数据。
- 不实现自己的服务端，不托管用户媒体，不代理用户媒体流。
- 不把 NAS 地址、用户名、音乐库、播放记录上传到开发者服务器。
- 不为每个后端复制一套 UI，统一通过抽象后的音乐库接口驱动现有页面。
- 不优先做 Plex 账号登录和自动发现，先支持手动服务器地址和 token。

## 推荐阶段

### 阶段 1：多音乐源基础架构

目标是把现有 Synology-only 结构改成 provider-neutral 结构。

需要新增或调整：

- `ServerProfile` 增加服务类型字段，例如 `providerType`。
- 统一登录结果，避免 `AppSession` 只保存 `SynologyClient`。
- 抽象统一音乐库客户端，例如 `MusicLibraryClient`。
- 让首页、浏览、搜索、播放、下载通过统一接口读取数据。
- 本地歌单、历史记录、下载记录里的歌曲 ID 改为全局唯一 ID。

建议全局 ID 格式：

```text
providerType + serverProfileID + remoteItemID
```

示例：

```text
jellyfin:server-uuid:item-id
emby:server-uuid:item-id
plex:server-uuid:rating-key
synology:server-uuid:song-id
```

### 阶段 2：优先支持 Jellyfin 和 Emby

Jellyfin 和 Emby 接口体系接近，适合一起设计适配器。

第一版只做：

- 手动填写服务器地址。
- 用户名密码登录。
- 选择音乐库。
- 浏览歌曲、专辑、歌手、歌单。
- 搜索音乐。
- 播放音频。
- 获取封面。
- 下载歌曲。

暂时不做：

- 视频库。
- Live TV。
- 照片。
- 服务端用户管理。
- 服务端播放进度写回。
- 多用户家庭共享管理。

### 阶段 3：支持 Plex 音乐

Plex 接入放在 Jellyfin / Emby 稳定之后。

第一版建议只做：

- 手动填写 Plex Server 地址。
- 手动填写 `X-Plex-Token`。
- 扫描音乐库。
- 浏览艺术家、专辑、歌曲和歌单。
- 播放、封面、下载。

后续再考虑：

- Plex 账号登录。
- 自动发现服务器。
- 远程访问服务器选择。
- Plex Pass 相关能力。

## 建议架构

### Provider 类型

```swift
enum MusicProviderType: String, Codable, CaseIterable {
    case synologyAudioStation
    case jellyfin
    case emby
    case plex
}
```

### 统一音乐库客户端

建议抽象一个最小接口，先覆盖现有页面真正需要的能力：

```swift
protocol MusicLibraryClient {
    var providerType: MusicProviderType { get }
    var profileID: UUID { get }

    func loadLibraries() async throws -> [MusicLibrary]
    func loadHome(libraryID: String?) async throws -> LibraryHomeSnapshot
    func loadSongs(libraryID: String?, offset: Int, limit: Int) async throws -> [Song]
    func loadAlbums(libraryID: String?, offset: Int, limit: Int) async throws -> [Album]
    func loadArtists(libraryID: String?, offset: Int, limit: Int) async throws -> [Artist]
    func loadPlaylists(libraryID: String?) async throws -> [Playlist]
    func search(_ query: String, libraryID: String?) async throws -> [Song]
    func coverURL(for itemID: String, size: CGSize?) -> URL?
    func streamURL(for song: Song, quality: AudioQuality) -> URL?
}
```

注意：实际写代码时可以按项目现有模型拆得更细，不需要一次性抽象过度。第一版接口应以“能替换现有 Synology 调用点”为准。

### 统一会话

现有 `AppSession` 不应长期只保存 `SynologyClient`。建议演进为：

```swift
final class AppSession: ObservableObject {
    @Published private(set) var musicClient: MusicLibraryClient?
}
```

为了降低风险，可以先保留 `SynologyClient`，增加兼容属性：

```swift
var client: SynologyClient?
var musicClient: MusicLibraryClient?
```

等页面都迁移完成后，再删除 Synology-only 会话依赖。

## 各服务接入注意事项

### Synology Audio Station

保持现有能力，作为默认 provider。

注意事项：

- QuickConnect 是 Synology 特有能力，不能扩展到 Jellyfin / Emby / Plex。
- Audio Station 的歌曲、封面、歌词、文件夹 API 与其它后端差异很大，需要通过 adapter 层隔离。
- 现有本地歌单和历史记录要兼容旧数据。

### Jellyfin

适合做第一批多后端支持。

注意事项：

- 通常通过用户名密码认证获得 access token。
- 音乐库需要从用户视图或库列表中筛选音乐类型。
- `ItemId` 不能直接和其它 provider 的 ID 混用。
- 播放 URL、封面 URL 一般都需要携带 token。
- 需要处理自签名证书和局域网 HTTPS。
- 只读取音乐相关 Item，避免误展示视频库。

官方参考：

- Jellyfin API: https://api.jellyfin.org/
- Jellyfin Docs: https://jellyfin.org/docs/

### Emby

可与 Jellyfin 共用大部分设计，但不要假设完全兼容。

注意事项：

- Emby 支持 API key 和用户认证，第一版建议只做用户名密码登录。
- 音频串流接口可直接用于播放，但要确认格式参数和转码行为。
- Emby 和 Jellyfin 返回字段相似但不完全一致，需要独立 DTO。
- 不要把 Emby 的视频能力暴露到 UI。

官方参考：

- Emby REST API: https://dev.emby.media/doc/restapi/index.html
- Emby Audio Streaming: https://dev.emby.media/doc/restapi/Audio-Streaming.html

### Plex

建议第二批做，因为接入方式和数据模型更特殊。

注意事项：

- 第一版使用手动 `X-Plex-Token`，不要先做 Plex 账号 OAuth。
- Plex 音乐库通常通过 library section 类型筛选。
- Plex 的主要 ID 往往是 `ratingKey`，需要映射到统一歌曲 ID。
- API 可能返回 XML 或 JSON，解析层要隔离。
- 远程访问、服务器发现、账号设备列表先不做。

官方参考：

- Plex Media Server URL Commands: https://support.plex.tv/articles/201638786-plex-media-server-url-commands/
- Plex Developer Portal: https://developer.plex.tv/

## UI 改造原则

### 添加服务器

新增服务器时先选择类型：

- Synology Audio Station
- Jellyfin
- Emby
- Plex

不同类型展示不同字段：

- Synology：QuickConnect / 地址、账号、密码、证书设置。
- Jellyfin：服务器地址、账号、密码、证书设置。
- Emby：服务器地址、账号、密码、证书设置。
- Plex：服务器地址、`X-Plex-Token`。

### 首页和浏览页

页面不要出现“Synology 专属文案”。应逐步改成：

- “服务器”
- “音乐库”
- “NAS / 自建音乐库”
- “私人音乐库”

保留品牌说明时，应放到关于页或连接类型说明里。

### 搜索

第一版搜索只搜索当前服务器和当前音乐库。

后续可以做：

- 当前服务器全库搜索。
- 多服务器统一搜索。
- 搜索结果按来源分组。

### 播放器

播放器不应该关心歌曲来自哪个后端，只依赖 `Song` 和 `streamURL`。

需要特别处理：

- token 过期时刷新。
- URL 失效时重新生成。
- 播放中切换服务器时的状态。
- 下载歌曲和远程歌曲的优先级。

## 付费策略

多音乐源支持适合作为完整功能的一部分。

可纳入完整功能的点：

- Jellyfin / Emby / Plex 音乐库。
- 多服务器配置。
- 跨服务器统一搜索。
- 多服务器本地歌单。
- 离线下载。
- iCloud 同步服务器配置。
- 小组件、灵动岛、锁屏歌词。
- 高级播放器样式、均衡器、淡入淡出。

免费版建议仍保持：

- 允许连接 1 个服务器。
- 如果用户选择 Jellyfin / Emby / Plex，可作为同一个“服务器配置”额度计算。
- 高级能力仍由完整功能解锁。

## 数据和隐私

当前隐私策略可以继续坚持：

- 服务器地址、用户名、token 保存在本机。
- 密码和 token 使用 Keychain。
- iCloud 同步只同步用户选择的配置，不上传到开发者服务器。
- 不收集用户媒体库、播放记录、搜索记录。
- 不接入广告和统计 SDK。

如果后续加入崩溃分析、统计 SDK、开发者服务器、账号系统，就必须重新检查 App Store 隐私申报。

## 风险清单

- 不同 provider 的封面 URL 可能需要认证，不能简单缓存裸 URL。
- Jellyfin / Emby 可能返回转码 URL，也可能返回直连文件，需要根据格式和服务器能力处理。
- Plex token 手动输入体验不好，但第一版风险最低。
- 多 provider 后，现有 `Song.id`、历史记录、下载记录、歌单收藏容易发生 ID 冲突。
- 旧 Synology 用户数据迁移要谨慎，不能破坏既有用户的服务器配置和本地歌单。
- App Review 里不要暗示支持盗版资源或公开影视资源站。
- 不要在截图和审核备注里暴露真实 NAS 地址。

## 开发顺序建议

1. 增加 `MusicProviderType` 和 provider-neutral 的 profile 字段。
2. 新增 `MusicLibraryClient` 最小协议。
3. 给现有 Synology 包一层 `SynologyMusicLibraryClient`。
4. 把首页、浏览、搜索、播放、下载逐步迁移到统一接口。
5. 增加 Jellyfin 登录和音乐库读取。
6. 增加 Emby 登录和音乐库读取。
7. 打磨封面、播放、下载和错误提示。
8. 再做 Plex token 模式。
9. 最后做跨服务器搜索和统一歌单增强。

## 不做事项检查表

每次准备新增多后端能力前，先检查以下问题：

- 这个功能是否只服务音乐？
- 是否会引入视频播放器、字幕、转码或媒体服务器职责？
- 是否会要求开发者服务器保存用户媒体信息？
- 是否可以通过统一接口实现，而不是给某个后端写专属页面？
- 是否会影响现有 Synology 用户数据？
- 是否会改变 App Store 隐私申报？

只要任一问题答案不清晰，就先暂停实现，重新评估。
