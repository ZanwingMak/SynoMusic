package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"log"
	"runtime"
	"strings"

	"github.com/egoist/mygo"
)

var desktopTray *playerTray

type playerTray struct {
	icon                                  *mygo.Tray
	menu                                  *mygo.Menu
	track, toggle, previous, next, show   *mygo.MenuItem
	mini, queue, settings, quit, controls *mygo.MenuItem
	song                                  Song
	playing, closeToTray                  bool
	language                              string
}

// trayIcon 使用透明的单色声波图标，系统可按菜单栏和任务栏外观自动着色。
func trayIcon() []byte {
	img := image.NewNRGBA(image.Rect(0, 0, 32, 32))
	for index, height := range []int{10, 18, 26, 18, 10} {
		x0, y0 := 4+index*5, (32-height)/2
		for y := y0; y < y0+height; y++ {
			for x := x0; x < x0+3; x++ {
				if (y == y0 || y == y0+height-1) && x != x0+1 {
					continue
				}
				img.SetNRGBA(x, y, color.NRGBA{A: 255})
			}
		}
	}
	var data bytes.Buffer
	if err := png.Encode(&data, img); err != nil {
		log.Printf("encode tray icon: %v", err)
	}
	return data.Bytes()
}

// setupTray 在应用就绪后建立原生入口，创建失败时保留正常的窗口关闭行为。
func setupTray(service *Service) {
	p := &playerTray{closeToTray: true}
	// command 把操作交给现有播放器，隐藏窗口时也只使用同一份音频与队列。
	command := func(name string, reveal bool) func(*mygo.MenuItem, *mygo.Window) {
		return func(*mygo.MenuItem, *mygo.Window) {
			if reveal {
				openWindow()
			}
			playbackCommand.Broadcast(name)
		}
	}
	p.track = &mygo.MenuItem{Disabled: true}
	p.toggle = &mygo.MenuItem{Click: command("toggle", false)}
	p.previous = &mygo.MenuItem{Click: command("previous", false)}
	p.next = &mygo.MenuItem{Click: command("next", false)}
	p.show = &mygo.MenuItem{Click: command("show-main", true)}
	p.mini = &mygo.MenuItem{Click: command("mini-player", true)}
	p.queue = &mygo.MenuItem{Click: command("show-queue", true)}
	p.settings = &mygo.MenuItem{Click: command("show-settings", true)}
	p.controls = &mygo.MenuItem{Accelerator: "CmdOrCtrl+Shift+T", Click: func(*mygo.MenuItem, *mygo.Window) {
		if mainWindow != nil && !mainWindow.IsDestroyed() {
			p.menu.PopupAt(mainWindow, mainWindow.Bounds().Width-24, 54)
		}
	}}
	p.quit = &mygo.MenuItem{Click: func(*mygo.MenuItem, *mygo.Window) { mygo.App.Quit() }}
	p.menu = mygo.NewMenu([]*mygo.MenuItem{p.track, mygo.Separator(), p.toggle, p.previous, p.next,
		mygo.Separator(), p.show, p.mini, p.queue, p.settings, mygo.Separator(), p.quit})
	var err error
	p.icon, err = mygo.NewTray(mygo.TrayOptions{ID: "synomusic-player", Icon: trayIcon(), IconIsTemplate: true, ToolTip: "SynoMusic", Menu: p.menu})
	if err != nil {
		log.Printf("create system tray: %v", err)
		return
	}
	desktopTray = p
	if runtime.GOOS == "windows" {
		p.icon.OnClick(func() { openWindow(); playbackCommand.Broadcast("show-main") })
	}
	service.mu.Lock()
	language, closeToTray := service.state.Settings["language"], service.state.Settings["closeToTray"] != "false"
	service.mu.Unlock()
	if language == "" {
		if preferred := mygo.App.PreferredLanguages(); len(preferred) > 0 {
			language = preferred[0]
		}
	}
	p.language, p.closeToTray = language, closeToTray
	p.refresh()
	mygo.App.OnWillQuit(func(*mygo.QuitEvent) { p.icon.Destroy() })
}

// updateTrayPreferences 在持久化成功后同步托盘语言和关闭偏好，所有原生状态都在主线程更新。
func updateTrayPreferences(language string, closeToTray bool) {
	if !mygo.App.IsReady() {
		return
	}
	mygo.RunOnMain(func() {
		if desktopTray != nil {
			if language == "" {
				language = desktopTray.language
			}
			if desktopTray.language == language && desktopTray.closeToTray == closeToTray {
				return
			}
			desktopTray.language = language
			desktopTray.closeToTray = closeToTray
			desktopTray.refresh()
		}
	})
}

// updateTrayPlayback 仅在曲目信息或播放状态变化时重建菜单，进度更新不会反复刷新托盘。
func updateTrayPlayback(song Song, playing bool) {
	if !mygo.App.IsReady() {
		return
	}
	mygo.RunOnMain(func() {
		p := desktopTray
		if p == nil || (p.song.ID == song.ID && p.song.Title == song.Title && p.song.Artist == song.Artist && p.playing == playing) {
			return
		}
		p.song, p.playing = song, playing
		p.refresh()
	})
}

// trayText 与客户端的七种语言一致，系统区域标签会回退到对应语言。
func trayText(language string) []string {
	labels := map[string][]string{
		"en":      {"No track selected", "Play", "Pause", "Previous track", "Next track", "Show SynoMusic", "Mini player", "Open full player", "Play queue", "Settings", "Quit SynoMusic", "Tray player…"},
		"zh-Hans": {"尚未选择歌曲", "播放", "暂停", "上一首", "下一首", "显示主窗口", "迷你播放器", "打开完整播放器", "播放队列", "设置", "退出 SynoMusic", "托盘播放器…"},
		"zh-Hant": {"尚未選擇歌曲", "播放", "暫停", "上一首", "下一首", "顯示主視窗", "迷你播放器", "開啟完整播放器", "播放佇列", "設定", "結束 SynoMusic", "選單列播放器…"},
		"ja":      {"曲が選択されていません", "再生", "一時停止", "前の曲", "次の曲", "メインウインドウを表示", "ミニプレイヤー", "フルプレイヤーを開く", "再生キュー", "設定", "SynoMusicを終了", "メニューバープレイヤー…"},
		"ko":      {"선택한 곡 없음", "재생", "일시 정지", "이전 곡", "다음 곡", "메인 윈도우 보기", "미니 플레이어", "전체 플레이어 열기", "재생 대기열", "설정", "SynoMusic 종료", "트레이 플레이어…"},
		"de":      {"Kein Titel ausgewählt", "Wiedergabe", "Pause", "Vorheriger Titel", "Nächster Titel", "SynoMusic anzeigen", "Mini-Player", "Vollständigen Player öffnen", "Warteschlange", "Einstellungen", "SynoMusic beenden", "Player im Infobereich…"},
		"fr":      {"Aucun titre sélectionné", "Lire", "Pause", "Titre précédent", "Titre suivant", "Afficher SynoMusic", "Mini-lecteur", "Ouvrir le lecteur complet", "File d’attente", "Réglages", "Quitter SynoMusic", "Lecteur dans la barre des menus…"},
	}
	if strings.HasPrefix(language, "zh") {
		if strings.Contains(language, "Hant") || strings.Contains(language, "TW") || strings.Contains(language, "HK") {
			language = "zh-Hant"
		} else {
			language = "zh-Hans"
		}
	} else {
		language = strings.Split(language, "-")[0]
	}
	if text, ok := labels[language]; ok {
		return text
	}
	return labels["en"]
}

// refresh 将真实曲目和窗口状态写入原生菜单，不显示虚构的播放信息。
func (p *playerTray) refresh() {
	text := trayText(p.language)
	title, artist := "SynoMusic", text[0]
	if p.song.ID != "" {
		title = strings.Join(strings.Fields(p.song.Title), " ")
		artist = strings.Join(strings.Fields(p.song.Artist), " ")
	}
	p.track.SetLabel(title)
	p.track.SetSubtitle(artist)
	p.toggle.SetLabel(text[1])
	if p.playing {
		p.toggle.SetLabel(text[2])
	}
	for _, item := range []*mygo.MenuItem{p.toggle, p.previous, p.next, p.queue} {
		item.SetEnabled(p.song.ID != "")
	}
	p.previous.SetLabel(text[3])
	p.next.SetLabel(text[4])
	p.show.SetLabel(text[5])
	p.mini.SetLabel(text[6])
	if miniPlayerActive {
		p.mini.SetLabel(text[7])
	}
	p.queue.SetLabel(text[8])
	p.settings.SetLabel(text[9])
	p.quit.SetLabel(text[10])
	p.controls.SetLabel(text[11])
	p.icon.SetToolTip(title + " — " + artist)
	p.icon.SetMenu(p.menu)
}
