package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/egoist/mygo"
	"github.com/zalando/go-keyring"
)

// Profile 与手机端导入导出的服务器配置保持相同字段。
type Profile struct {
	ID                       string `json:"id"`
	Provider                 string `json:"providerType"`
	Name                     string `json:"name"`
	Scheme                   string `json:"scheme"`
	Host                     string `json:"host"`
	Port                     int    `json:"port"`
	Username                 string `json:"username"`
	LibraryID                string `json:"musicLibraryID,omitempty"`
	QuickConnectID           string `json:"quickConnectID,omitempty"`
	IsQuickConnect           bool   `json:"isQuickConnect"`
	IgnoreInvalidCertificate bool   `json:"ignoreInvalidCertificate"`
	Folder                   string `json:"folder,omitempty"`
	BasePath                 string `json:"basePath,omitempty"`
}

// Song 统一服务器、本地文件、电台及播客的可播放条目。
type Song struct {
	ID          string   `json:"id"`
	ProfileID   string   `json:"profileID"`
	Title       string   `json:"title"`
	Artist      string   `json:"artist"`
	Album       string   `json:"album"`
	Genre       string   `json:"genre"`
	Duration    float64  `json:"duration"`
	Track       int      `json:"trackNumber"`
	Codec       string   `json:"codec"`
	Artwork     string   `json:"artwork"`
	Path        string   `json:"path,omitempty"`
	AlbumArtist string   `json:"albumArtist,omitempty"`
	Year        int      `json:"year,omitempty"`
	Disc        int      `json:"discNumber,omitempty"`
	Bitrate     int      `json:"bitrate,omitempty"`
	SampleRate  int      `json:"sampleRate,omitempty"`
	TrackGain   *float64 `json:"trackGain,omitempty"`
	AlbumGain   *float64 `json:"albumGain,omitempty"`
	TrackPeak   float64  `json:"trackPeak,omitempty"`
	AlbumPeak   float64  `json:"albumPeak,omitempty"`
}

// Playlist 保存不受数量限制的本地歌单。
type Playlist struct {
	ID    string         `json:"id"`
	Name  string         `json:"name"`
	Songs []Song         `json:"songs"`
	Smart *SmartPlaylist `json:"smart,omitempty"`
}

// State 保存无需远端账号的用户资料，凭证单独存入钥匙串。
type State struct {
	UpdatedAt     int64                `json:"updatedAt"`
	Cached        []Song               `json:"cached"`
	Profiles      []Profile            `json:"profiles"`
	Playlists     []Playlist           `json:"playlists"`
	History       []Song               `json:"history"`
	Imports       []Song               `json:"imports"`
	Favorites     []string             `json:"favorites"`
	FavoriteSongs []Song               `json:"favoriteSongs"`
	Settings      map[string]string    `json:"settings"`
	Lyrics        map[string]string    `json:"lyrics"`
	Podcasts      []Podcast            `json:"podcasts"`
	Stats         map[string]SongStats `json:"stats"`
}

// Service 向桌面前端提供类型安全的音乐能力。
type Service struct {
	mu            sync.Mutex
	downloadMu    sync.Mutex
	state         State
	dir           string
	clients       map[string]*libraryClient
	songs         map[string]Song
	lyricsRetryAt time.Time
}

var seekCommand = mygo.NewEvent[float64]("seekCommand")

// newService 恢复磁盘状态，不保存密码到 JSON。
func newService() (*Service, error) {
	restoreLocalAccess()
	base, err := desktopConfigDir()
	if err != nil {
		return nil, err
	}
	dir := filepath.Join(base, "SynoMusic")
	if override := os.Getenv("SYNOMUSIC_DATA_DIR"); override != "" {
		dir = override
	}
	if err = os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	s := &Service{dir: dir, clients: map[string]*libraryClient{}, songs: map[string]Song{}}
	s.state = State{Profiles: []Profile{}, Playlists: []Playlist{}, History: []Song{}, Imports: []Song{}, Favorites: []string{}, Settings: map[string]string{}, Lyrics: map[string]string{}, Podcasts: []Podcast{}}
	data, err := os.ReadFile(filepath.Join(dir, "library.json"))
	if err == nil {
		if err = json.Unmarshal(data, &s.state); err != nil {
			return nil, fmt.Errorf("read library: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if s.state.Settings == nil {
		s.state.Settings = map[string]string{}
	}
	if s.state.Stats == nil {
		s.state.Stats = map[string]SongStats{}
	}
	if s.state.Lyrics == nil {
		s.state.Lyrics = map[string]string{}
	}
	if s.state.Cached == nil {
		s.state.Cached = []Song{}
	}
	if s.state.Imports == nil {
		s.state.Imports = []Song{}
	}
	if s.state.History == nil {
		s.state.History = []Song{}
	}
	if s.state.Profiles == nil {
		s.state.Profiles = []Profile{}
	}
	if s.state.Playlists == nil {
		s.state.Playlists = []Playlist{}
	}
	if s.state.Favorites == nil {
		s.state.Favorites = []string{}
	}
	if s.state.Podcasts == nil {
		s.state.Podcasts = []Podcast{}
	}
	for _, song := range append(append([]Song{}, s.state.Imports...), append(append([]Song{}, s.state.Cached...), s.state.History...)...) {
		s.songs[song.ID] = song
	}
	for _, list := range s.state.Playlists {
		for _, song := range list.Songs {
			s.songs[song.ID] = song
		}
	}
	return s, nil
}

// newID 创建随机标识符，用于跨客户端导入和本地条目。
func newID() string {
	var data [16]byte
	if _, err := rand.Read(data[:]); err != nil {
		panic(err)
	}
	b := hex.EncodeToString(data[:])
	return b[:8] + "-" + b[8:12] + "-" + b[12:16] + "-" + b[16:20] + "-" + b[20:]
}

// saveLocked 使用原子替换保存资料；调用方必须持有状态锁。
func (s *Service) saveLocked() error {
	s.state.UpdatedAt = time.Now().UnixMilli()
	return s.persistLocked()
}

// persistLocked 保存云端原始时间，避免同步本身制造新版本。
func (s *Service) persistLocked() error {
	data, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}
	temp := filepath.Join(s.dir, "library.json.tmp")
	if err = os.WriteFile(temp, data, 0600); err != nil {
		return err
	}
	return os.Rename(temp, filepath.Join(s.dir, "library.json"))
}

// Snapshot 返回状态副本，避免前端更新与后台操作发生数据竞争。
func (s *Service) Snapshot() (State, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.FavoriteSongs = s.favoriteSongsLocked()
	data, err := json.Marshal(s.state)
	if err != nil {
		return State{}, err
	}
	var state State
	err = json.Unmarshal(data, &state)
	return state, err
}

// SaveProfile 验证连接并将密码写入系统钥匙串，支持任意数量的服务器。
func (s *Service) SaveProfile(p Profile, password string, otp string) (Profile, error) {
	if p.ID == "" {
		p.ID = newID()
	}
	if p.Name == "" {
		p.Name = p.Host
	}
	if p.Provider == "" {
		p.Provider = "synologyAudioStation"
	}
	if password == "" {
		password = credential(p.ID)
	}
	client, err := connectLibrary(p, password, otp)
	if err != nil {
		return p, err
	}
	p = client.profile
	if password != "" {
		if err = keyring.Set("app.synomusic.SynoMusic.desktop", p.ID, password); err != nil {
			return p, fmt.Errorf("save credential: %w", err)
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clients[p.ID] = client
	found := false
	for i := range s.state.Profiles {
		if s.state.Profiles[i].ID == p.ID {
			s.state.Profiles[i] = p
			found = true
		}
	}
	if !found {
		s.state.Profiles = append(s.state.Profiles, p)
	}
	return p, s.saveLocked()
}

// RemoveProfile 移除配置与钥匙串凭证，保留用户创建的本地歌单。
func (s *Service) RemoveProfile(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := []Profile{}
	for _, p := range s.state.Profiles {
		if p.ID != id {
			result = append(result, p)
		}
	}
	s.state.Profiles = result
	delete(s.clients, id)
	_ = keyring.Delete("app.synomusic.SynoMusic.desktop", id)
	if runtime.GOOS == "darwin" {
		_ = keyring.Delete("app.synomusic.SynoMusic.mac", id)
	}
	return s.saveLocked()
}

// client 恢复所选音乐源的会话，避免将凭证交给网页。
func (s *Service) client(id string) (*libraryClient, error) {
	s.mu.Lock()
	client := s.clients[id]
	var profile Profile
	for _, p := range s.state.Profiles {
		if p.ID == id {
			profile = p
			break
		}
	}
	s.mu.Unlock()
	if client != nil {
		return client, nil
	}
	if profile.ID == "" {
		return nil, errors.New("server not found")
	}
	password := credential(id)
	client, err := connectLibrary(profile, password, "")
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	s.clients[id] = client
	s.mu.Unlock()
	return client, nil
}

// Songs 拉取全部分页并登记播放条目，不在前端暴露令牌。
func (s *Service) Songs(profileID string) ([]Song, error) {
	if profileID == "local" {
		s.mu.Lock()
		defer s.mu.Unlock()
		return append([]Song{}, s.state.Imports...), nil
	}
	c, err := s.client(profileID)
	if err != nil {
		return nil, err
	}
	songs, err := c.loadSongs()
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, song := range songs {
		s.songs[song.ID] = song
	}
	if data, err := json.Marshal(songs); err == nil {
		path := s.libraryCachePath(profileID)
		if os.MkdirAll(filepath.Dir(path), 0700) == nil && os.WriteFile(path+".tmp", data, 0600) == nil {
			_ = os.Rename(path+".tmp", path)
		}
	}
	return songs, nil
}

// libraryCachePath 使用固定摘要保存资料库快照，避免配置标识符成为文件路径。
func (s *Service) libraryCachePath(profileID string) string {
	sum := sha256.Sum256([]byte(profileID))
	return filepath.Join(s.dir, "Libraries", hex.EncodeToString(sum[:])+".json")
}

// CachedLibrary 恢复最近成功读取的资料库，让网络异常时仍可浏览与播放已下载歌曲。
func (s *Service) CachedLibrary(profileID string) []Song {
	s.mu.Lock()
	defer s.mu.Unlock()
	if profileID == "local" {
		return append([]Song{}, s.state.Imports...)
	}
	songs := []Song{}
	if data, err := os.ReadFile(s.libraryCachePath(profileID)); err == nil {
		if json.Unmarshal(data, &songs) != nil {
			songs = []Song{}
		}
	}
	seen := map[string]bool{}
	for _, song := range songs {
		seen[song.ID] = true
		s.songs[song.ID] = song
	}
	for _, song := range append(append([]Song{}, s.state.Cached...), s.state.History...) {
		if song.ProfileID == profileID && !seen[song.ID] {
			songs = append(songs, song)
			seen[song.ID] = true
		}
	}
	return songs
}

// CreatePlaylist 创建本地歌单，名称不能为空。
func (s *Service) CreatePlaylist(name string) (Playlist, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Playlist{}, errors.New("name is required")
	}
	p := Playlist{ID: newID(), Name: name, Songs: []Song{}}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Playlists = append(s.state.Playlists, p)
	return p, s.saveLocked()
}

// SavePlaylist 更新歌单内容并保存播放所需的条目快照。
func (s *Service) SavePlaylist(p Playlist) error {
	if err := validateSmartPlaylist(p.Smart); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.state.Playlists {
		if s.state.Playlists[i].ID == p.ID {
			p.Name = strings.TrimSpace(p.Name)
			if p.Name == "" {
				return errors.New("name is required")
			}
			s.state.Playlists[i] = p
			for _, song := range p.Songs {
				s.songs[song.ID] = song
			}
			return s.saveLocked()
		}
	}
	return errors.New("playlist not found")
}

// DeletePlaylist 删除指定歌单，不删除原始音乐文件。
func (s *Service) DeletePlaylist(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := []Playlist{}
	for _, p := range s.state.Playlists {
		if p.ID != id {
			result = append(result, p)
		}
	}
	s.state.Playlists = result
	return s.saveLocked()
}

// ToggleFavorite 切换喜欢状态，返回切换后的收藏状态。
func (s *Service) ToggleFavorite(id string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, v := range s.state.Favorites {
		if v == id {
			s.state.Favorites = append(s.state.Favorites[:i], s.state.Favorites[i+1:]...)
			s.state.FavoriteSongs = s.favoriteSongsLocked()
			return false, s.saveLocked()
		}
	}
	if _, ok := s.songs[id]; !ok {
		return false, errors.New("song not found")
	}
	s.state.Favorites = append(s.state.Favorites, id)
	s.state.FavoriteSongs = s.favoriteSongsLocked()
	return true, s.saveLocked()
}

// RecordPlay 更新最近播放记录并避免重复，最多保留五百条。
func (s *Service) RecordPlay(song Song) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	history := []Song{song}
	for _, v := range s.state.History {
		if v.ID != song.ID && len(history) < 500 {
			history = append(history, v)
		}
	}
	s.state.History = history
	s.songs[song.ID] = song
	if song.Duration > 0 {
		for index, item := range s.state.Imports {
			if item.ID == song.ID {
				s.state.Imports[index] = song
				break
			}
		}
	}
	return s.saveLocked()
}

// SaveSettings 保存用户偏好，不因购买状态改变任何设置。
func (s *Service) SaveSettings(settings map[string]string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Settings = settings
	return s.saveLocked()
}

// SaveLyrics 保存每首歌的自定义 LRC 或纯文本歌词。
func (s *Service) SaveLyrics(id string, text string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Lyrics[id] = text
	return s.saveLocked()
}

// UpdateNowPlaying 同步系统媒体控制中心和媒体键状态。
func (s *Service) UpdateNowPlaying(song Song, playing bool, position float64, rate float64) {
	if rate < 0.5 || rate > 2 {
		rate = 1
	}
	state := mygo.PlaybackPaused
	if playing {
		state = mygo.PlaybackPlaying
	}
	mygo.NowPlaying.Set(mygo.NowPlayingInfo{Title: song.Title, Artist: song.Artist, Album: song.Album,
		Duration: time.Duration(song.Duration * float64(time.Second)), Position: time.Duration(position * float64(time.Second)), State: state, Rate: rate,
		Commands: mygo.MediaPlay | mygo.MediaPause | mygo.MediaNext | mygo.MediaPrevious | mygo.MediaSeek})
}

// seekEvent 将系统进度条跳转传给当前播放器。
func (s *Service) seekEvent(position float64) { seekCommand.Broadcast(position) }

// ExportProfiles 导出与手机端兼容且不含密码的服务器配置。
func (s *Service) ExportProfiles() (bool, error) {
	path, err := mygo.Dialog.Save(mygo.SaveDialogOptions{Title: "Export servers", DefaultPath: "SynoMusic-Servers.json", Filters: []mygo.FileFilter{{Name: "JSON", Extensions: []string{"json"}}}})
	if err != nil || path == "" {
		return false, err
	}
	s.mu.Lock()
	data, err := json.MarshalIndent(map[string]any{"version": 1, "exportedAt": time.Now().UTC().Format(time.RFC3339), "profiles": s.state.Profiles}, "", "  ")
	s.mu.Unlock()
	if err != nil {
		return false, err
	}
	return true, os.WriteFile(path, data, 0600)
}

// ImportProfiles 合并不含密码的服务器配置，保留现有音乐源。
func (s *Service) ImportProfiles() (int, error) {
	paths, err := mygo.Dialog.Open(mygo.OpenDialogOptions{Title: "Import servers", Filters: []mygo.FileFilter{{Name: "JSON", Extensions: []string{"json"}}}})
	if err != nil || len(paths) == 0 {
		return 0, err
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		return 0, err
	}
	var payload struct {
		Profiles []Profile `json:"profiles"`
		Servers  []Profile `json:"servers"`
	}
	if err = json.Unmarshal(data, &payload); err != nil {
		return 0, err
	}
	profiles := payload.Profiles
	if len(profiles) == 0 {
		profiles = payload.Servers
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	seen := map[string]bool{}
	for _, p := range s.state.Profiles {
		seen[p.ID] = true
	}
	count := 0
	for _, p := range profiles {
		if p.ID == "" {
			p.ID = newID()
		}
		if !seen[p.ID] {
			s.state.Profiles = append(s.state.Profiles, p)
			seen[p.ID] = true
			count++
		}
	}
	return count, s.saveLocked()
}

// sortedSongs 按唱片序号和标题排序，保持专辑播放顺序稳定。
func sortedSongs(songs []Song) {
	sort.SliceStable(songs, func(i, j int) bool {
		if a, b := strings.ToLower(songs[i].Album), strings.ToLower(songs[j].Album); a != b {
			return a < b
		}
		if songs[i].Disc != songs[j].Disc {
			return songs[i].Disc < songs[j].Disc
		}
		if songs[i].Track != songs[j].Track {
			return songs[i].Track < songs[j].Track
		}
		return strings.ToLower(songs[i].Title) < strings.ToLower(songs[j].Title)
	})
}

// Platform 返回真实运行平台，避免用浏览器特征猜测桌面能力。
func (s *Service) Platform() string { return runtime.GOOS }

// credential 优先读取统一凭据服务，并兼容早期 Mac 凭据名称。
func credential(id string) string {
	value, err := keyring.Get("app.synomusic.SynoMusic.desktop", id)
	if err != nil && runtime.GOOS == "darwin" {
		value, _ = keyring.Get("app.synomusic.SynoMusic.mac", id)
	}
	return value
}

// CloudSupported 仅在带有 Apple 配置描述文件的 Mac 应用中展示 iCloud 能力。
func (s *Service) CloudSupported() bool {
	if runtime.GOOS != "darwin" {
		return false
	}
	executable, err := os.Executable()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(filepath.Dir(executable), "..", "embedded.provisionprofile"))
	return err == nil
}
