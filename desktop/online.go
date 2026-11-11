package main

import (
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/egoist/mygo"
)

// Podcast 保存公开 RSS 节目的订阅信息。
type Podcast struct {
	ID         string `json:"id"`
	Title      string `json:"title"`
	Author     string `json:"author"`
	FeedURL    string `json:"feedURL"`
	ArtworkURL string `json:"artworkURL"`
}

// publicJSON 拉取无凭证的公开 API，使用超时及响应大小限制。
func publicJSON(address string, target any) error {
	client := &http.Client{Timeout: 20 * time.Second}
	req, err := http.NewRequest("GET", address, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "SynoMusic/1.6.5 (Desktop)")
	resp, err := client.Do(req)
	if err != nil {
		return errors.New("online service unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("online service returned HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 16<<20)).Decode(target)
}

// Radio 搜索 Radio Browser 的公开电台，并登记可播放条目。
func (s *Service) Radio(keyword string) ([]Song, error) {
	address := "https://de1.api.radio-browser.info/json/stations/topvote?limit=60&hidebroken=true"
	if strings.TrimSpace(keyword) != "" {
		address = "https://de1.api.radio-browser.info/json/stations/search?" + url.Values{"name": {keyword}, "limit": {"60"}, "hidebroken": {"true"}}.Encode()
	}
	var stations []struct {
		ID      string `json:"stationuuid"`
		Name    string `json:"name"`
		URL     string `json:"url_resolved"`
		Artwork string `json:"favicon"`
		Country string `json:"country"`
		Tags    string `json:"tags"`
	}
	if err := publicJSON(address, &stations); err != nil {
		return nil, err
	}
	songs := []Song{}
	for _, station := range stations {
		u, err := url.Parse(station.URL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
			continue
		}
		songs = append(songs, Song{ID: "radio:" + station.ID, ProfileID: "radio", Title: station.Name, Artist: station.Country, Album: "Radio", Genre: station.Tags, Path: station.URL, Artwork: station.Artwork})
	}
	s.mu.Lock()
	for _, song := range songs {
		s.songs[song.ID] = song
	}
	s.mu.Unlock()
	return songs, nil
}

// SearchPodcasts 通过 Apple Podcasts 公共接口搜索节目。
func (s *Service) SearchPodcasts(keyword string, country string) ([]Podcast, error) {
	if country == "" {
		country = "US"
	}
	var result struct {
		Results []struct {
			ID      int    `json:"collectionId"`
			Title   string `json:"collectionName"`
			Author  string `json:"artistName"`
			Feed    string `json:"feedUrl"`
			Artwork string `json:"artworkUrl600"`
		} `json:"results"`
	}
	address := "https://itunes.apple.com/search?" + url.Values{"term": {keyword}, "media": {"podcast"}, "entity": {"podcast"}, "country": {country}, "limit": {"40"}}.Encode()
	if err := publicJSON(address, &result); err != nil {
		return nil, err
	}
	shows := []Podcast{}
	for _, r := range result.Results {
		if r.Feed != "" {
			shows = append(shows, Podcast{ID: fmt.Sprint(r.ID), Title: r.Title, Author: r.Author, FeedURL: r.Feed, ArtworkURL: r.Artwork})
		}
	}
	return shows, nil
}

// PodcastEpisodes 解析公开 RSS 音频附件，不抓取节目授权范围以外的内容。
func (s *Service) PodcastEpisodes(show Podcast) ([]Song, error) {
	u, err := url.Parse(show.FeedURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return nil, errors.New("invalid podcast feed")
	}
	client := &http.Client{Timeout: 25 * time.Second}
	resp, err := client.Get(u.String())
	if err != nil {
		return nil, errors.New("podcast feed unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("podcast HTTP %d", resp.StatusCode)
	}
	var feed struct {
		Channel struct {
			Items []struct {
				Title     string `xml:"title"`
				GUID      string `xml:"guid"`
				Duration  string `xml:"duration"`
				Enclosure struct {
					URL string `xml:"url,attr"`
				} `xml:"enclosure"`
			} `xml:"item"`
		} `xml:"channel"`
	}
	if err = xml.NewDecoder(io.LimitReader(resp.Body, 24<<20)).Decode(&feed); err != nil {
		return nil, err
	}
	songs := []Song{}
	for _, item := range feed.Channel.Items {
		if item.Enclosure.URL == "" {
			continue
		}
		audioURL, err := url.Parse(item.Enclosure.URL)
		if err != nil || (audioURL.Scheme != "https" && audioURL.Scheme != "http") {
			continue
		}
		duration := 0.0
		for _, component := range strings.Split(strings.TrimSpace(item.Duration), ":") {
			seconds, _ := strconv.ParseFloat(component, 64)
			duration = duration*60 + seconds
		}
		songs = append(songs, Song{ID: fileID("podcast", audioURL.String()), ProfileID: "podcast", Title: item.Title, Artist: show.Author, Album: show.Title, Path: audioURL.String(), Artwork: show.ArtworkURL, Duration: duration})
	}
	s.mu.Lock()
	for _, song := range songs {
		s.songs[song.ID] = song
	}
	s.mu.Unlock()
	return songs, nil
}

// Subscribe 保存或移除播客订阅。
func (s *Service) Subscribe(show Podcast, enabled bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := []Podcast{}
	for _, p := range s.state.Podcasts {
		if p.ID != show.ID {
			result = append(result, p)
		}
	}
	if enabled {
		result = append(result, show)
	}
	s.state.Podcasts = result
	return s.saveLocked()
}

// Lyrics 优先读取用户编辑歌词，其次读取文件旁的 LRC 或音乐服务器歌词。
func (s *Service) Lyrics(id string) (string, error) {
	s.mu.Lock()
	custom, hasCustom := s.state.Lyrics[id]
	song, ok := s.songs[id]
	s.mu.Unlock()
	if hasCustom {
		return custom, nil
	}
	if !ok {
		return "", errors.New("song not found")
	}
	if song.ProfileID == "local" {
		path := strings.TrimSuffix(song.Path, filepath.Ext(song.Path)) + ".lrc"
		data, err := os.ReadFile(path)
		if os.IsNotExist(err) {
			return "", nil
		}
		return string(data), err
	}
	if song.ProfileID == "radio" || song.ProfileID == "podcast" {
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
			position := number(line["Start"]) / 1e7
			lines = append(lines, fmt.Sprintf("[%02d:%05.2f]%s", int(position)/60, float64(int(position)%60)+position-float64(int(position)), str(line["Text"])))
		}
		return strings.Join(lines, "\n"), nil
	}
	return "", nil
}

// OpenLink 仅允许打开公开网页和音乐搜索地址。
func (s *Service) OpenLink(address string) error {
	u, err := url.Parse(address)
	if err != nil || u.Hostname() == "" || (u.Scheme != "https" && u.Scheme != "http") {
		return errors.New("invalid website address")
	}
	return mygo.Shell.OpenExternal(u.String())
}
