package main

import (
	"encoding/json"
	"errors"
	"time"
)

// SyncCloud 将 Mac 配置同步到用户私有 iCloud 数据库，保留本机文件路径与缓存。
func (s *Service) SyncCloud() (bool, error) {
	s.mu.Lock()
	if s.state.Settings["icloud"] != "true" {
		s.mu.Unlock()
		return false, errors.New("enable iCloud sync first")
	}
	snapshot := s.state
	snapshot.Imports = nil
	snapshot.Cached = nil
	snapshot.Settings = map[string]string{}
	for key, value := range s.state.Settings {
		snapshot.Settings[key] = value
	}
	data, err := json.Marshal(snapshot)
	updatedAt := s.state.UpdatedAt
	s.mu.Unlock()
	if err != nil {
		return false, err
	}
	if updatedAt == 0 {
		updatedAt = time.Now().UnixMilli()
	}
	remote, remoteDate, err := syncNativeCloud(data, updatedAt)
	if err != nil {
		return false, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(remote) > 0 && remoteDate > s.state.UpdatedAt && s.state.UpdatedAt == updatedAt {
		var incoming State
		if err = json.Unmarshal(remote, &incoming); err != nil {
			return false, err
		}
		incoming.Imports = s.state.Imports
		incoming.Cached = s.state.Cached
		incoming.UpdatedAt = remoteDate
		if incoming.Settings == nil {
			incoming.Settings = map[string]string{}
		}
		incoming.Settings["icloud"] = "true"
		if incoming.Lyrics == nil {
			incoming.Lyrics = map[string]string{}
		}
		s.state = incoming
		s.clients = map[string]*libraryClient{}
		for _, list := range s.state.Playlists {
			for _, song := range list.Songs {
				s.songs[song.ID] = song
			}
		}
		for _, song := range s.state.History {
			s.songs[song.ID] = song
		}
	}
	s.state.Settings["lastCloudSync"] = time.Now().Format(time.RFC3339)
	return true, s.persistLocked()
}
