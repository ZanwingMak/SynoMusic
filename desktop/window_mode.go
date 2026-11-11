package main

import "github.com/egoist/mygo"

var fullPlayerBounds mygo.Rectangle
var miniPlayerActive bool
var fullPlayerFullscreen bool

// SetMiniPlayer 在同一窗口切换迷你播放器，音频、队列与原窗口位置保持不变。
func (s *Service) SetMiniPlayer(enabled bool) {
	if mainWindow == nil || mainWindow.IsDestroyed() || miniPlayerActive == enabled {
		return
	}
	miniPlayerActive = enabled
	if enabled {
		fullPlayerBounds = mainWindow.Bounds()
		fullPlayerFullscreen = mainWindow.IsFullScreen()
		mainWindow.SetFullScreen(false)
		mainWindow.SetMinimumSize(380, 190)
		mainWindow.SetContentSize(420, 210)
		mainWindow.SetAlwaysOnTop(true)
	} else {
		mainWindow.SetAlwaysOnTop(false)
		mainWindow.SetMinimumSize(980, 680)
		mainWindow.SetBounds(fullPlayerBounds)
		if fullPlayerFullscreen {
			mainWindow.SetFullScreen(true)
		}
	}
}

// SetPlayerOnTop 仅切换迷你播放器的置顶偏好，不改变系统其他窗口。
func (s *Service) SetPlayerOnTop(enabled bool) {
	if miniPlayerActive && mainWindow != nil {
		mainWindow.SetAlwaysOnTop(enabled)
	}
}
