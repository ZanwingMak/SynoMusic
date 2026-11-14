package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/dhowden/tag"
)

// Lyrics 优先读取用户编辑、本地内嵌或服务器歌词；缺失时按用户偏好查询公开歌词库。
func (s *Service) Lyrics(id string) (string, error) {
	s.mu.Lock()
	custom, hasCustom := s.state.Lyrics[id]
	song, ok := s.songs[id]
	online := s.state.Settings["onlineLyrics"] != "false"
	s.mu.Unlock()
	if hasCustom {
		return custom, nil
	}
	if !ok {
		return "", errors.New("song not found")
	}
	if song.ProfileID == "radio" || song.ProfileID == "podcast" {
		return "", nil
	}
	text, sourceError := s.sourceLyrics(song)
	if strings.TrimSpace(text) != "" {
		return text, nil
	}
	if !online {
		return "", sourceError
	}
	return s.onlineLyrics(song)
}

// sourceLyrics 读取已授权音频的旁置 LRC、内嵌歌词或音乐服务器时间轴，保留原始文本。
func (s *Service) sourceLyrics(song Song) (string, error) {
	if song.ProfileID == "local" {
		path := strings.TrimSuffix(song.Path, filepath.Ext(song.Path)) + ".lrc"
		if data, err := os.ReadFile(path); err == nil && len(data) <= 2<<20 && strings.TrimSpace(string(data)) != "" {
			return string(data), nil
		}
		file, err := os.Open(song.Path)
		if err != nil {
			return "", err
		}
		defer file.Close()
		if metadata, err := tag.ReadFrom(file); err == nil {
			return metadata.Lyrics(), nil
		}
		return "", nil
	}
	c, err := s.client(song.ProfileID)
	if err != nil {
		return "", err
	}
	if c.profile.Provider == "synologyAudioStation" {
		data, err := c.jsonRequest("GET", "/webapi/AudioStation/lyrics.cgi", url.Values{"api": {"SYNO.AudioStation.Lyrics"}, "version": {"2"}, "method": {"getlyrics"}, "id": {song.Path}, "_sid": {c.sessionToken()}}, nil)
		if err != nil {
			return "", err
		}
		return str(obj(data["data"])["lyrics"]), nil
	}
	if c.profile.Provider == "jellyfin" || c.profile.Provider == "emby" {
		data, err := c.jsonRequest("GET", "/Audio/"+url.PathEscape(song.Path)+"/Lyrics", nil, nil)
		if err != nil {
			return "", nil
		}
		lines := []string{}
		for _, raw := range arr(data["Lyrics"]) {
			line := obj(raw)
			if _, timed := line["Start"]; !timed {
				lines = append(lines, str(line["Text"]))
				continue
			}
			position := number(line["Start"]) / 1e7
			lines = append(lines, fmt.Sprintf("[%02d:%05.2f]%s", int(position)/60, math.Mod(position, 60), str(line["Text"])))
		}
		return strings.Join(lines, "\n"), nil
	}
	return "", nil
}

// lyricsRecord 保留在线服务提供的真实同步时间；纯文本不生成估算时间轴。
type lyricsRecord struct {
	Title        string  `json:"trackName"`
	Artist       string  `json:"artistName"`
	Album        string  `json:"albumName"`
	Duration     float64 `json:"duration"`
	Instrumental bool    `json:"instrumental"`
	Synced       string  `json:"syncedLyrics"`
	Plain        string  `json:"plainLyrics"`
}

// lyricText 优先返回同步歌词，器乐曲不误套用其他版本的歌词。
func (record lyricsRecord) lyricText() string {
	if record.Instrumental {
		return ""
	}
	if strings.TrimSpace(record.Synced) != "" {
		return record.Synced
	}
	return record.Plain
}

// normalizedLyricTag 仅归一化大小写和空白，保留 Live 等版本信息以避免错配。
func normalizedLyricTag(value string) string {
	return strings.ToLower(strings.Join(strings.Fields(value), " "))
}

// lyricsRequest 使用独立无凭证 HTTP 客户端，并遵守歌词服务的请求限制。
func (s *Service) lyricsRequest(path string, query url.Values, result any) (bool, error) {
	s.mu.Lock()
	limited := time.Now().Before(s.lyricsRetryAt)
	s.mu.Unlock()
	if limited {
		return false, errors.New("lyrics service is busy; try again later")
	}
	req, err := http.NewRequest("GET", "https://lrclib.net/api/"+path+"?"+query.Encode(), nil)
	if err != nil {
		return false, err
	}
	req.Header.Set("User-Agent", "SynoMusic Desktop/1.6.9 (https://github.com/ZanwingMak/SynoMusic)")
	response, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		return false, errors.New("online lyrics unavailable; check your connection")
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusNotFound {
		return false, nil
	}
	if response.StatusCode == http.StatusTooManyRequests {
		delay, _ := strconv.Atoi(response.Header.Get("Retry-After"))
		until := time.Now().Add(time.Duration(max(delay, 60)) * time.Second)
		if date, err := http.ParseTime(response.Header.Get("Retry-After")); err == nil && date.After(until) {
			until = date
		}
		s.mu.Lock()
		s.lyricsRetryAt = until
		s.mu.Unlock()
		return false, errors.New("lyrics service is busy; try again later")
	}
	if response.StatusCode != http.StatusOK {
		return false, errors.New("online lyrics unavailable; try again later")
	}
	return true, json.NewDecoder(io.LimitReader(response.Body, 2<<20)).Decode(result)
}

// onlineLyrics 精确匹配后再搜索标题、艺人与时长，缓存成功结果供离线阅读。
func (s *Service) onlineLyrics(song Song) (string, error) {
	if strings.TrimSpace(song.Title) == "" {
		return "", nil
	}
	key := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%s\x00%s\x00%.0f", song.Title, song.Artist, song.Album, song.Duration)))
	cache := filepath.Join(s.dir, "Lyrics", hex.EncodeToString(key[:])+".lrc")
	if data, err := os.ReadFile(cache); err == nil && len(data) <= 2<<20 {
		return string(data), nil
	}
	query := url.Values{"track_name": {strings.TrimSpace(song.Title)}}
	if song.Artist != "" {
		query.Set("artist_name", strings.TrimSpace(song.Artist))
	}
	var selected lyricsRecord
	if song.Artist != "" {
		exact := query.Encode()
		params, _ := url.ParseQuery(exact)
		if song.Album != "" {
			params.Set("album_name", song.Album)
		}
		if song.Duration >= 1 && song.Duration <= 3600 {
			params.Set("duration", fmt.Sprintf("%.0f", song.Duration))
		}
		found, err := s.lyricsRequest("get", params, &selected)
		if err != nil {
			return "", err
		}
		if found {
			return s.cacheLyrics(cache, selected.lyricText()), nil
		}
	}
	var candidates []lyricsRecord
	if _, err := s.lyricsRequest("search", query, &candidates); err != nil {
		return "", err
	}
	best := -1
	for _, candidate := range candidates {
		if candidate.Instrumental || normalizedLyricTag(candidate.Title) != normalizedLyricTag(song.Title) || (song.Artist != "" && normalizedLyricTag(candidate.Artist) != normalizedLyricTag(song.Artist)) {
			continue
		}
		if song.Duration > 0 && (candidate.Duration <= 0 || math.Abs(song.Duration-candidate.Duration) > 8) {
			continue
		}
		score := 0
		if normalizedLyricTag(candidate.Album) == normalizedLyricTag(song.Album) {
			score += 4
		}
		if math.Abs(candidate.Duration-song.Duration) <= 2 {
			score += 2
		}
		if candidate.Synced != "" {
			score++
		}
		if score > best && candidate.lyricText() != "" {
			selected = candidate
			best = score
		}
	}
	return s.cacheLyrics(cache, selected.lyricText()), nil
}

// cacheLyrics 只缓存匹配成功的歌词，不把网络错误或无匹配永久记作空结果。
func (s *Service) cacheLyrics(path, text string) string {
	if strings.TrimSpace(text) != "" && os.MkdirAll(filepath.Dir(path), 0700) == nil {
		_ = os.WriteFile(path, []byte(text), 0600)
	}
	return text
}
