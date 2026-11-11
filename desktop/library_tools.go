package main

import (
	"errors"
	"os"
	"strings"

	"github.com/egoist/mygo"
)

// RemoveLocalSong 只移除本机资料库索引与本地歌单引用，不删除用户的原始音频。
func (s *Service) RemoveLocalSong(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	remaining := []Song{}
	found := false
	for _, song := range s.state.Imports {
		if song.ID == id {
			found = true
		} else {
			remaining = append(remaining, song)
		}
	}
	if !found {
		return errors.New("local song not found")
	}
	s.state.Imports = remaining
	for index, playlist := range s.state.Playlists {
		songs := []Song{}
		for _, song := range playlist.Songs {
			if song.ID != id {
				songs = append(songs, song)
			}
		}
		s.state.Playlists[index].Songs = songs
	}
	return s.saveLocked()
}

// RevealLocalSong 在系统文件管理器显示已经导入并获授权的音频。
func (s *Service) RevealLocalSong(id string) error {
	s.mu.Lock()
	var path string
	for _, song := range s.state.Imports {
		if song.ID == id {
			path = song.Path
			break
		}
	}
	s.mu.Unlock()
	if path == "" {
		return errors.New("local song not found")
	}
	if _, err := os.Stat(path); err != nil {
		return err
	}
	mygo.Shell.ShowItemInFolder(path)
	return nil
}

// ImportLyrics 读取用户选择的 UTF-8 LRC 或纯文本文件，不自动覆盖当前歌曲。
func (s *Service) ImportLyrics() (string, error) {
	paths, err := mygo.Dialog.Open(mygo.OpenDialogOptions{Title: "Import lyrics", Filters: []mygo.FileFilter{{Name: "Lyrics", Extensions: []string{"lrc", "txt"}}}})
	if err != nil || len(paths) == 0 {
		return "", err
	}
	info, err := os.Stat(paths[0])
	if err != nil {
		return "", err
	}
	if info.Size() > 2<<20 {
		return "", errors.New("lyrics file is too large")
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		return "", err
	}
	return strings.TrimPrefix(string(data), "\ufeff"), nil
}

// ExportLyrics 保存用户正在编辑的歌词，LRC 时间标记保持原样。
func (s *Service) ExportLyrics(text string) (bool, error) {
	if len(text) > 2<<20 {
		return false, errors.New("lyrics file is too large")
	}
	path, err := mygo.Dialog.Save(mygo.SaveDialogOptions{Title: "Export lyrics", DefaultPath: "SynoMusic-Lyrics", Filters: []mygo.FileFilter{{Name: "Lyrics", Extensions: []string{"lrc", "txt"}}}})
	if err != nil || path == "" {
		return false, err
	}
	return true, os.WriteFile(path, []byte(text), 0600)
}
