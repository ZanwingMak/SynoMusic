# SynoMusic

> A native iOS music client for your own library: Synology Audio Station, Plex, Jellyfin, Emby, WebDAV, SMB, and local imports.

[English](README.md) · [简体中文](README.zh.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[Official Website](https://zanwingmak.github.io/SynoMusic/) · [Privacy Policy](https://zanwingmak.github.io/SynoMusic/privacy.html) · [Terms of Use](https://zanwingmak.github.io/SynoMusic/terms.html)

SynoMusic is built for people who keep music on their own servers. It connects only to music libraries you authorize, keeps credentials in iOS Keychain, and brings a polished iPhone player with lyrics, downloads, widgets, Lock Screen controls, Dynamic Island, and theme customization.

## Screenshots

|  Library  |  Browse  |  Settings  |
| :---: | :---: | :---: |
| ![Library](docs/screenshots/01-library.png) | ![Browse](docs/screenshots/02-browse.png) | ![Settings](docs/screenshots/03-settings.png) |

|  Full Player  |  Server Editor  |
| :---: | :---: |
| ![Player](docs/screenshots/04-player.png) | ![Editor](docs/screenshots/05-editor.png) |

## Features

- **Multiple music sources**: Synology Audio Station, Plex, Jellyfin, Emby, WebDAV, SMB, and local imports.
- **Music only**: Jellyfin, Emby, Plex, WebDAV, and SMB integrations are scoped to music libraries, not video, TV, or photos.
- **Private connections**: Multiple server profiles, Keychain credentials, HTTPS, self-signed certificate trust, QuickConnect, Plex authorization, and WebDAV/SMB folder selection.
- **Native playback**: AVQueuePlayer, AirPlay, Lock Screen controls, Dynamic Island, playback queue, sleep timer, and format fallback.
- **Library browsing**: Albums, artists, genres, folders, playlists, all songs, search, smart mixes, favorites, and playback history.
- **Lyrics and metadata**: Synced lyrics, lyric editing, online lookup, cover search, and song/artist information search.
- **Offline and import**: Song downloads, download queue, local file import, and link-based music import.
- **System integration**: Widgets, Siri shortcuts, iCloud configuration sync, alternate app icons, and theme colors.
- **Languages**: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, German, and French.

## Requirements

- iPhone or iPad running **iOS 17 or later**.
- At least one supported music source or local audio files.
- For server sources, you need an account/token with permission to access the music library.

## Build from source

This project is generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/ZanwingMak/SynoMusic.git
cd SynoMusic
xcodegen generate
open SynoMusic.xcodeproj
```

Set your own development team in Xcode -> Signing & Capabilities, then run on a simulator or device.

## Project layout

```text
SynoMusic/
├── App/                 # @main entry + RootView
├── Audio/               # PlaybackEngine, NowPlaying, Live Activity bridge
├── DesignSystem/        # Theme, ThemeManager, L10n, Typography, Components
├── Features/            # Library, Browse, Search, Settings, Player, Purchase
├── Models/              # Song / Album / Artist / Playlist / ServerProfile
├── Providers/           # Plex, Jellyfin, Emby, WebDAV, SMB, local music
├── Storage/             # ServerStore, PlaylistStore, KeychainStore, downloads
├── Synology/            # Synology Audio Station integration
└── SynoMusicLive/       # Widget extension: Live Activity + Lock Screen
```

## Disclaimer

SynoMusic is an unofficial client. Synology, Plex, Jellyfin, Emby, WebDAV, SMB, Apple, and related names belong to their respective owners. SynoMusic is not affiliated with or endorsed by those projects or companies.

## License

This project is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).
