# SynoMusic

> 面向私人音乐库的原生 iOS 音乐客户端：支持 Synology Audio Station、Plex、Jellyfin、Emby、WebDAV、SMB 和本地导入。

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[官网](https://zanwingmak.github.io/SynoMusic-OpenSource/) · [隐私政策](https://zanwingmak.github.io/SynoMusic-OpenSource/privacy.html) · [服务条款](https://zanwingmak.github.io/SynoMusic-OpenSource/terms.html)

SynoMusic 适合把音乐保存在自己服务器或本地文件中的用户。App 只连接你授权的音乐库，凭证保存在 iOS Keychain，并提供精致播放器、歌词、下载、小组件、锁屏控制、灵动岛和主题定制。

## 截图

|  资料库  |  浏览  |  设置  |
| :---: | :---: | :---: |
| ![Library](docs/screenshots/01-library.png) | ![Browse](docs/screenshots/02-browse.png) | ![Settings](docs/screenshots/03-settings.png) |

|  播放页  |  服务器编辑  |
| :---: | :---: |
| ![Player](docs/screenshots/04-player.png) | ![Editor](docs/screenshots/05-editor.png) |

## 功能

- **多音乐源**：Synology Audio Station、Plex、Jellyfin、Emby、WebDAV、SMB、本地导入。
- **仅限音乐**：Jellyfin、Emby、Plex、WebDAV、SMB 只接入音乐库，不包含视频、电视或照片功能。
- **私有连接**：多服务器配置、Keychain 凭证、HTTPS、自签名证书信任、QuickConnect、Plex 授权、WebDAV/SMB 目录选择。
- **原生播放**：AVQueuePlayer、AirPlay、锁屏控制、灵动岛、播放队列、睡眠定时、格式兜底。
- **资料库浏览**：专辑、艺术家、流派、文件夹、歌单、所有歌曲、搜索、智能歌单、收藏和历史记录。
- **歌词与资料**：同步歌词、歌词编辑、在线歌词、封面查找、歌曲和歌手资料搜索。
- **离线与导入**：歌曲下载、下载队列、本地文件导入、链接下载导入。
- **系统集成**：小组件、Siri 捷径、iCloud 配置同步、备用 App 图标和主题色。
- **多语言**：简体中文、繁体中文、英语、日语、韩语、德语、法语。

## 要求

- iPhone 或 iPad，系统 **iOS 17 或更高版本**。
- 至少一个支持的音乐源，或本地音频文件。
- 服务器音乐源需要可访问音乐库的账号或 Token。

## 从源码构建

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成 Xcode 工程。

```bash
brew install xcodegen
git clone https://github.com/ZanwingMak/SynoMusic.git
cd SynoMusic
xcodegen generate
open SynoMusic.xcodeproj
```

在 Xcode -> Signing & Capabilities 中设置你的开发者团队后即可运行。

## 免责声明

SynoMusic 是非官方客户端。Synology、Plex、Jellyfin、Emby、WebDAV、SMB、Apple 等名称归各自所有者所有；SynoMusic 与这些项目或公司没有从属或背书关系。

## 许可证

本项目使用 **GNU General Public License v3.0**。详见 [LICENSE](LICENSE)。
