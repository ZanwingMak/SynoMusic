package main

import (
	"encoding/json"
	"os"
)

// favoriteSongsLocked 从已保存快照与各音乐源缓存恢复收藏，离线和切换音乐源后仍可显示；调用方持锁。
func (s *Service) favoriteSongsLocked() []Song {
	known := map[string]Song{}
	for _, song := range s.state.FavoriteSongs {
		known[song.ID] = song
	}
	for _, song := range s.state.Imports {
		known[song.ID] = song
	}
	for id, song := range s.songs {
		known[id] = song
	}
	missing := false
	for _, id := range s.state.Favorites {
		if _, ok := known[id]; !ok {
			missing = true
			break
		}
	}
	if missing {
		for _, profile := range s.state.Profiles {
			var songs []Song
			if data, err := os.ReadFile(s.libraryCachePath(profile.ID)); err == nil && json.Unmarshal(data, &songs) == nil {
				for _, song := range songs {
					if _, exists := known[song.ID]; !exists {
						known[song.ID] = song
					}
				}
			}
		}
	}
	result := []Song{}
	for _, id := range s.state.Favorites {
		if song, ok := known[id]; ok {
			result = append(result, song)
			s.songs[id] = song
		}
	}
	return result
}
