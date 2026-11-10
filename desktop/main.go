package main

import (
	"log"
	"net/http"
	"runtime"
	"strings"
	"time"

	"github.com/egoist/mygo"
)

var mainWindow *mygo.Window
var quitting bool
var navigationCommand = mygo.NewEvent[string]("navigationCommand")

var playbackCommand = mygo.NewEvent[string]("playbackCommand")

// main 装配桌面服务、原生菜单、系统媒体键与 跨平台主窗口。
func main() {
	mygo.App.SetName("SynoMusic")
	mygo.App.OnBeforeQuit(func(*mygo.QuitEvent) { quitting = true })
	mygo.App.OnOpenURL(func(address string) {
		if mainWindow != nil {
			mainWindow.Show()
			mainWindow.Focus()
		}
		if strings.Contains(address, "smart-mixes") {
			navigationCommand.Broadcast("mixes")
		} else if strings.Contains(address, "downloads") {
			navigationCommand.Broadcast("downloads")
		} else if strings.Contains(address, "history") {
			navigationCommand.Broadcast("history")
		}
	})
	service, err := newService()
	if err != nil {
		log.Fatal(err)
	}
	mygo.Bind(service)
	mygo.Protocol.Handle("music", http.HandlerFunc(service.serveMedia))
	mygo.App.WhenReady(func() {
		mygo.App.SetMenu(mygo.NewMenu([]*mygo.MenuItem{
			{Role: mygo.RoleAppMenu},
			{Label: "File", Submenu: []*mygo.MenuItem{
				{Label: "Import Music…", Accelerator: "CmdOrCtrl+O", Click: func(*mygo.MenuItem, *mygo.Window) { playbackCommand.Broadcast("import") }},
				{Label: "Add Server…", Accelerator: "CmdOrCtrl+N", Click: func(*mygo.MenuItem, *mygo.Window) { playbackCommand.Broadcast("server") }},
				mygo.Separator(), {Role: mygo.RoleClose},
			}},
			{Role: mygo.RoleEditMenu},
			{Label: "Playback", Submenu: []*mygo.MenuItem{
				{Label: "Play / Pause", Accelerator: "CmdOrCtrl+P", Click: func(*mygo.MenuItem, *mygo.Window) { playbackCommand.Broadcast("toggle") }},
				{Label: "Next Track", Accelerator: "CmdOrCtrl+Right", Click: func(*mygo.MenuItem, *mygo.Window) { playbackCommand.Broadcast("next") }},
				{Label: "Previous Track", Accelerator: "CmdOrCtrl+Left", Click: func(*mygo.MenuItem, *mygo.Window) { playbackCommand.Broadcast("previous") }},
			}},
			{Role: mygo.RoleViewMenu}, {Role: mygo.RoleWindowMenu},
		}))
		openWindow()
	})
	mygo.NowPlaying.OnCommand(func(command mygo.MediaCommand, position time.Duration) {
		commands := map[mygo.MediaCommand]string{mygo.MediaPlay: "play", mygo.MediaPause: "pause", mygo.MediaNext: "next", mygo.MediaPrevious: "previous"}
		if command == mygo.MediaSeek {
			service.seekEvent(position.Seconds())
			return
		}
		if name, ok := commands[command]; ok {
			playbackCommand.Broadcast(name)
		}
	})
	mygo.App.OnWindowAllClosed(func() {
		if runtime.GOOS != "darwin" {
			mygo.App.Quit()
		}
	})
	mygo.App.OnActivate(func(visible bool) {
		if !visible {
			openWindow()
		}
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}

// openWindow 保留 Windows 原生标题栏，Mac 使用融合侧栏并在关闭窗口后继续播放。
func openWindow() {
	if mainWindow != nil && !mainWindow.IsDestroyed() {
		mainWindow.Show()
		mainWindow.Focus()
		return
	}
	titleBar := mygo.TitleBarDefault
	if runtime.GOOS == "darwin" {
		titleBar = mygo.TitleBarHidden
	}
	mainWindow = mygo.NewWindow(mygo.WindowOptions{Title: "SynoMusic", Width: 1420, Height: 920, MinWidth: 980, MinHeight: 680,
		TitleBarStyle: titleBar, TitleBarHeight: 54, BackgroundColor: "light-dark(#f8f8fa, #18191d)", URL: "/"})
	if runtime.GOOS == "darwin" {
		mainWindow.OnClose(func(event *mygo.CloseEvent) {
			if !quitting {
				event.PreventDefault()
				mainWindow.Hide()
			}
		})
	}
}
