package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/egoist/mygo"
)

// PlaylistImportResult 明确报告无法匹配的条目，不悄悄替换成其他歌曲。
type PlaylistImportResult struct {
	Playlist Playlist `json:"playlist"`
	Missing  int      `json:"missing"`
}

// ExportPlaylist 通过系统保存窗口导出 M3U8 或完整 JSON，不写入服务器凭证。
func (s *Service) ExportPlaylist(playlist Playlist) (bool, error) {
	if strings.TrimSpace(playlist.Name) == "" || len(playlist.Songs) > 10000 {
		return false, errors.New("invalid playlist")
	}
	path, err := mygo.Dialog.Save(mygo.SaveDialogOptions{Title: "Export playlist", DefaultPath: "SynoMusic-Playlist.m3u8", Filters: []mygo.FileFilter{{Name: "M3U8 playlist", Extensions: []string{"m3u8"}}, {Name: "SynoMusic playlist", Extensions: []string{"json"}}}})
	if err != nil || path == "" {
		return false, err
	}
	var data []byte
	if strings.EqualFold(filepath.Ext(path), ".json") {
		data, err = json.MarshalIndent(playlist, "", "  ")
	} else {
		var text strings.Builder
		text.WriteString("#EXTM3U\n#PLAYLIST:" + playlistLine(playlist.Name) + "\n")
		for _, song := range playlist.Songs {
			metadata, marshalErr := json.Marshal(song)
			if marshalErr != nil {
				return false, marshalErr
			}
			text.WriteString("#SYNOMUSIC:" + base64.RawStdEncoding.EncodeToString(metadata) + "\n")
			text.WriteString(fmt.Sprintf("#EXTINF:%d,%s - %s\n", int(song.Duration), playlistLine(song.Artist), playlistLine(song.Title)))
			entry := song.Path
			if entry == "" || (song.ProfileID != "local" && song.ProfileID != "radio") {
				entry = "synomusic://track?id=" + url.QueryEscape(song.ID)
			}
			if parsed, parseErr := url.Parse(entry); parseErr == nil && parsed.User != nil {
				return false, errors.New("playlist URLs must not contain credentials")
			}
			text.WriteString(playlistLine(entry) + "\n")
		}
		data = []byte(text.String())
	}
	if err != nil {
		return false, err
	}
	return true, os.WriteFile(path, data, 0600)
}

// playlistLine 防止标签换行破坏 M3U 条目结构。
func playlistLine(value string) string {
	return strings.NewReplacer("\r", " ", "\n", " ").Replace(value)
}

// ImportPlaylist 导入 M3U、M3U8 和 JSON，只匹配已有资料库或无凭证的公开音频流。
func (s *Service) ImportPlaylist() (PlaylistImportResult, error) {
	paths, err := mygo.Dialog.Open(mygo.OpenDialogOptions{Title: "Import playlist", Filters: []mygo.FileFilter{{Name: "Playlists", Extensions: []string{"m3u", "m3u8", "json"}}}})
	if err != nil || len(paths) == 0 {
		return PlaylistImportResult{}, err
	}
	info, err := os.Stat(paths[0])
	if err != nil {
		return PlaylistImportResult{}, err
	}
	if info.Size() > 16<<20 {
		return PlaylistImportResult{}, errors.New("playlist is too large")
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		return PlaylistImportResult{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	playlist := Playlist{ID: newID(), Name: strings.TrimSuffix(filepath.Base(paths[0]), filepath.Ext(paths[0])), Songs: []Song{}}
	result := PlaylistImportResult{}
	byPath := map[string]Song{}
	for _, song := range s.songs {
		if song.Path != "" {
			byPath[playlistPath(song.Path)] = song
		}
	}
	// 仅接受已知歌曲或用户配置的音乐源标识，导入内容不获得文件系统额外权限。
	appendSong := func(candidate Song, address string) {
		if len(playlist.Songs) >= 10000 {
			result.Missing++
			return
		}
		if existing, ok := s.songs[candidate.ID]; ok && candidate.ID != "" {
			playlist.Songs = append(playlist.Songs, existing)
			return
		}
		if existing, ok := byPath[playlistPath(address)]; ok && address != "" {
			playlist.Songs = append(playlist.Songs, existing)
			return
		}
		for _, profile := range s.state.Profiles {
			if candidate.ID != "" && candidate.ProfileID == profile.ID {
				playlist.Songs = append(playlist.Songs, candidate)
				return
			}
		}
		parsed, parseErr := url.Parse(address)
		if parseErr == nil && (parsed.Scheme == "http" || parsed.Scheme == "https") && parsed.Host != "" && parsed.User == nil {
			if candidate.Title == "" {
				candidate.Title = filepath.Base(parsed.Path)
			}
			candidate.ID = fileID("radio", address)
			candidate.ProfileID = "radio"
			candidate.Path = address
			playlist.Songs = append(playlist.Songs, candidate)
			return
		}
		result.Missing++
	}
	if strings.EqualFold(filepath.Ext(paths[0]), ".json") {
		var incoming Playlist
		if err = json.Unmarshal(data, &incoming); err != nil {
			return result, err
		}
		if err = validateSmartPlaylist(incoming.Smart); err != nil {
			return result, err
		}
		if strings.TrimSpace(incoming.Name) != "" {
			playlist.Name = strings.TrimSpace(incoming.Name)
		}
		playlist.Smart = incoming.Smart
		for _, song := range incoming.Songs {
			appendSong(song, song.Path)
		}
	} else {
		var candidate Song
		scanner := bufio.NewScanner(strings.NewReader(strings.TrimPrefix(string(data), "\ufeff")))
		scanner.Buffer(make([]byte, 4096), 256<<10)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if strings.HasPrefix(line, "#PLAYLIST:") {
				playlist.Name = strings.TrimSpace(strings.TrimPrefix(line, "#PLAYLIST:"))
				continue
			}
			if strings.HasPrefix(line, "#SYNOMUSIC:") {
				if raw, decodeErr := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(line, "#SYNOMUSIC:")); decodeErr == nil {
					_ = json.Unmarshal(raw, &candidate)
				}
				continue
			}
			if strings.HasPrefix(line, "#EXTINF:") {
				if parts := strings.SplitN(line, ",", 2); len(parts) == 2 && candidate.Title == "" {
					candidate.Title = parts[1]
				}
				continue
			}
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if parsed, parseErr := url.Parse(line); parseErr == nil && parsed.Scheme == "synomusic" {
				candidate.ID = parsed.Query().Get("id")
			}
			address := line
			if !strings.Contains(line, "://") && !filepath.IsAbs(line) {
				address = filepath.Join(filepath.Dir(paths[0]), line)
			}
			appendSong(candidate, address)
			candidate = Song{}
		}
		if err = scanner.Err(); err != nil {
			return result, err
		}
	}
	if playlist.Name == "" {
		playlist.Name = "Imported playlist"
	}
	if len(playlist.Songs) == 0 && playlist.Smart == nil {
		return result, errors.New("no matching songs; import the music library first")
	}
	s.state.Playlists = append(s.state.Playlists, playlist)
	for _, song := range playlist.Songs {
		s.songs[song.ID] = song
	}
	result.Playlist = playlist
	return result, s.saveLocked()
}

// playlistPath 统一不同平台的分隔符以匹配已有音频路径。
func playlistPath(path string) string {
	if parsed, err := url.Parse(path); err == nil && parsed.Scheme == "file" {
		path = parsed.Path
		if parsed.Host != "" {
			path = "//" + parsed.Host + path
		}
	}
	return filepath.Clean(strings.ReplaceAll(path, "\\", "/"))
}
