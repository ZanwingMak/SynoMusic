package main

import (
	"errors"
	"strings"
	"time"
)

// SongStats 保存本机评分、有效播放次数与最近播放时间。
type SongStats struct {
	Rating     int   `json:"rating"`
	PlayCount  int   `json:"playCount"`
	LastPlayed int64 `json:"lastPlayed"`
}

// PlaylistRule 表示智能歌单的一条可编辑筛选规则。
type PlaylistRule struct {
	Field    string `json:"field"`
	Operator string `json:"operator"`
	Value    string `json:"value"`
}

// SmartPlaylist 在指定音乐源中动态计算歌单，不复制或修改音频文件。
type SmartPlaylist struct {
	SourceID   string         `json:"sourceID"`
	Match      string         `json:"match"`
	Rules      []PlaylistRule `json:"rules"`
	Sort       string         `json:"sort"`
	Descending bool           `json:"descending"`
	Limit      int            `json:"limit"`
}

// validateSmartPlaylist 拒绝无效规则，旧版普通歌单保持兼容。
func validateSmartPlaylist(smart *SmartPlaylist) error {
	if smart == nil {
		return nil
	}
	if smart.SourceID == "" || (smart.Match != "all" && smart.Match != "any") || len(smart.Rules) > 20 || smart.Limit < 0 || smart.Limit > 10000 {
		return errors.New("invalid smart playlist")
	}
	fields := map[string]bool{"title": true, "artist": true, "album": true, "genre": true, "year": true, "duration": true, "rating": true, "playCount": true, "lastPlayed": true, "favorite": true, "downloaded": true, "codec": true}
	operators := map[string]bool{"contains": true, "notContains": true, "equals": true, "notEquals": true, "greater": true, "less": true, "withinDays": true, "olderDays": true}
	for _, rule := range smart.Rules {
		if !fields[rule.Field] || !operators[rule.Operator] || len(rule.Value) > 500 {
			return errors.New("invalid smart playlist rule")
		}
	}
	return nil
}

// SaveSmartPlaylist 在一次本机保存中创建或更新规则，避免产生空白中间歌单。
func (s *Service) SaveSmartPlaylist(playlist Playlist) (Playlist, error) {
	if err := validateSmartPlaylist(playlist.Smart); err != nil {
		return Playlist{}, err
	}
	playlist.Name = strings.TrimSpace(playlist.Name)
	if playlist.Name == "" || playlist.Smart == nil {
		return Playlist{}, errors.New("name and rules are required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	validSource := playlist.Smart.SourceID == "local"
	for _, profile := range s.state.Profiles {
		validSource = validSource || profile.ID == playlist.Smart.SourceID
	}
	if !validSource {
		return Playlist{}, errors.New("music source not found")
	}
	playlist.Songs = []Song{}
	if playlist.ID == "" {
		playlist.ID = newID()
		s.state.Playlists = append(s.state.Playlists, playlist)
	} else {
		found := false
		for index, existing := range s.state.Playlists {
			if existing.ID == playlist.ID {
				s.state.Playlists[index] = playlist
				found = true
				break
			}
		}
		if !found {
			return Playlist{}, errors.New("playlist not found")
		}
	}
	return playlist, s.saveLocked()
}

// RateSong 保存零到五星评分，零表示取消评分。
func (s *Service) RateSong(id string, rating int) (SongStats, error) {
	if id == "" || rating < 0 || rating > 5 {
		return SongStats{}, errors.New("rating must be between zero and five")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Stats == nil {
		s.state.Stats = map[string]SongStats{}
	}
	stats := s.state.Stats[id]
	stats.Rating = rating
	s.state.Stats[id] = stats
	return stats, s.saveLocked()
}

// RecordCompletedPlay 仅由达到有效聆听时长的播放器调用，不把拖动进度计为播放。
func (s *Service) RecordCompletedPlay(id string) (SongStats, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.songs[id]; !ok {
		return SongStats{}, errors.New("song not found")
	}
	if s.state.Stats == nil {
		s.state.Stats = map[string]SongStats{}
	}
	stats := s.state.Stats[id]
	stats.PlayCount++
	stats.LastPlayed = time.Now().UnixMilli()
	s.state.Stats[id] = stats
	return stats, s.saveLocked()
}

// ClearListeningHistory 清理本机最近播放列表，保留评分、次数与原始音频。
func (s *Service) ClearListeningHistory() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.History = []Song{}
	return s.saveLocked()
}
