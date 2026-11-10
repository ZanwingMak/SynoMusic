package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dhowden/tag"
	"github.com/egoist/mygo"
	"github.com/hirochachacha/go-smb2"
)

// audioFile 仅索引可播放音频，忽略其他用户文件。
func audioFile(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".mp3", ".m4a", ".aac", ".flac", ".wav", ".aiff", ".aif", ".ogg", ".opus", ".alac":
		return true
	}
	return false
}

// fileID 为本地与文件服务条目创建稳定的非路径标识符。
func fileID(profile, path string) string {
	sum := sha256.Sum256([]byte(profile + ":" + path))
	return profile + ":" + hex.EncodeToString(sum[:16])
}

// localSong 读取本地音频标签，缺失标签时使用文件名。
func localSong(path string) Song {
	song := Song{ID: fileID("local", path), ProfileID: "local", Title: strings.TrimSuffix(filepath.Base(path), filepath.Ext(path)), Album: filepath.Base(filepath.Dir(path)), Path: path, Codec: strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")}
	f, err := os.Open(path)
	if err != nil {
		return song
	}
	defer f.Close()
	metadata, err := tag.ReadFrom(f)
	if err == nil {
		if metadata.Title() != "" {
			song.Title = metadata.Title()
		}
		song.Artist = metadata.Artist()
		if metadata.Album() != "" {
			song.Album = metadata.Album()
		}
		song.Genre = metadata.Genre()
		song.Track, _ = metadata.Track()
	}
	song.Artwork = "music://localhost/artwork/" + url.PathEscape(song.ID)
	return song
}

// ImportMusic 通过原生文件选择器导入音频目录，并保留原文件位置。
func (s *Service) ImportMusic() (int, error) {
	paths, err := mygo.Dialog.Open(mygo.OpenDialogOptions{Title: "Import music folder", Directory: true, Multiple: true})
	if err != nil || len(paths) == 0 {
		return 0, err
	}
	songs := []Song{}
	for _, root := range paths {
		err = filepath.WalkDir(root, func(path string, d fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if d.IsDir() {
				if strings.HasPrefix(d.Name(), ".") && path != root {
					return filepath.SkipDir
				}
				return nil
			}
			if audioFile(path) {
				songs = append(songs, localSong(path))
			}
			return nil
		})
		if err != nil {
			return 0, err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	seen := map[string]bool{}
	for _, song := range s.state.Imports {
		seen[song.ID] = true
	}
	count := 0
	for _, song := range songs {
		if !seen[song.ID] {
			s.state.Imports = append(s.state.Imports, song)
			seen[song.ID] = true
			count++
		}
		s.songs[song.ID] = song
	}
	sortedSongs(s.state.Imports)
	return count, s.saveLocked()
}

// webDAVEntry 保留 WebDAV 资源路径和目录标记。
type webDAVEntry struct {
	Href     string `xml:"href"`
	Propstat []struct {
		Status string `xml:"status"`
		Prop   struct {
			ResourceType struct {
				Collection *struct{} `xml:"collection"`
			} `xml:"resourcetype"`
			DisplayName string `xml:"displayname"`
		} `xml:"prop"`
	} `xml:"propstat"`
}

// webDAVEntries 仅向配置的同源服务器发送 PROPFIND 与凭证。
func (c *libraryClient) webDAVEntries(address string) ([]webDAVEntry, error) {
	base, _ := url.Parse(c.base)
	u, err := url.Parse(address)
	if err != nil || u.Host != base.Host || u.Scheme != base.Scheme {
		return nil, errors.New("invalid WebDAV path")
	}
	req, err := c.request("PROPFIND", address, strings.NewReader(`<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>`))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Depth", "1")
	req.Header.Set("Content-Type", "application/xml")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, errors.New("WebDAV connection failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 207 {
		return nil, fmt.Errorf("WebDAV returned HTTP %d", resp.StatusCode)
	}
	var result struct {
		Responses []webDAVEntry `xml:"response"`
	}
	err = xml.NewDecoder(io.LimitReader(resp.Body, 32<<20)).Decode(&result)
	return result.Responses, err
}

// scanWebDAV 广度优先扫描目录，并阻止循环和跨源资源获取。
func (c *libraryClient) scanWebDAV() ([]Song, error) {
	root, _ := url.Parse(c.base + "/")
	pending := []string{root.String()}
	visited := map[string]bool{}
	songs := []Song{}
	for len(pending) > 0 {
		current := pending[0]
		pending = pending[1:]
		if visited[current] {
			continue
		}
		visited[current] = true
		entries, err := c.webDAVEntries(current)
		if err != nil {
			return nil, err
		}
		for _, entry := range entries {
			ref, err := url.Parse(entry.Href)
			if err != nil {
				continue
			}
			u := root.ResolveReference(ref)
			if u.Host != root.Host || u.Scheme != root.Scheme || !strings.HasPrefix(u.Path, root.Path) {
				continue
			}
			directory := false
			for _, ps := range entry.Propstat {
				if ps.Prop.ResourceType.Collection != nil {
					directory = true
				}
			}
			if directory {
				if !strings.HasSuffix(u.Path, "/") {
					u.Path += "/"
				}
				if !visited[u.String()] {
					pending = append(pending, u.String())
				}
				continue
			}
			if audioFile(u.Path) {
				name := filepath.Base(u.Path)
				songs = append(songs, Song{ID: fileID(c.profile.ID, u.String()), ProfileID: c.profile.ID, Title: strings.TrimSuffix(name, filepath.Ext(name)), Album: filepath.Base(filepath.Dir(u.Path)), Path: u.String(), Codec: strings.TrimPrefix(filepath.Ext(name), ".")})
			}
		}
	}
	sortedSongs(songs)
	return songs, nil
}

// withSMB 打开短生命周期 SMB 会话，确保关闭目录、会话与网络连接。
func (c *libraryClient) withSMB(fn func(*smb2.Share) error) error {
	host := strings.TrimPrefix(c.profile.Host, "smb://")
	host = strings.TrimSuffix(host, "/")
	if u, err := url.Parse("smb://" + host); err == nil {
		host = u.Hostname()
	}
	port := c.profile.Port
	if port <= 0 {
		port = 445
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, fmt.Sprint(port)), 12*time.Second)
	if err != nil {
		return errors.New("cannot connect to SMB server")
	}
	defer conn.Close()
	dialer := smb2.Dialer{Initiator: &smb2.NTLMInitiator{User: c.profile.Username, Password: c.password}}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	session, err := dialer.DialContext(ctx, conn)
	if err != nil {
		return errors.New("SMB authentication failed")
	}
	defer session.Logoff()
	shareName := strings.Split(strings.Trim(c.profile.Folder, "/\\"), "/")[0]
	if shareName == "" {
		return errors.New("SMB share name is required")
	}
	share, err := session.Mount(shareName)
	if err != nil {
		return errors.New("SMB share unavailable")
	}
	defer share.Umount()
	return fn(share)
}

// connectSMB 验证共享目录与认证信息。
func connectSMB(p Profile, password string) (*libraryClient, error) {
	c := &libraryClient{profile: p, password: password, http: &http.Client{Timeout: 45 * time.Second}}
	err := c.withSMB(func(share *smb2.Share) error { _, err := share.Stat("."); return err })
	return c, err
}

// scanSMB 递归索引用户选择的 SMB 共享目录。
func (c *libraryClient) scanSMB() ([]Song, error) {
	songs := []Song{}
	err := c.withSMB(func(share *smb2.Share) error {
		folder := strings.Trim(c.profile.Folder, "/\\")
		parts := strings.SplitN(folder, "/", 2)
		root := "."
		if len(parts) == 2 {
			root = parts[1]
		}
		pending := []string{root}
		for len(pending) > 0 {
			folder := pending[0]
			pending = pending[1:]
			entries, err := share.ReadDir(folder)
			if err != nil {
				return err
			}
			for _, info := range entries {
				path := filepath.Join(folder, info.Name())
				if info.IsDir() {
					if !strings.HasPrefix(info.Name(), ".") {
						pending = append(pending, path)
					}
					continue
				}
				if audioFile(path) {
					name := info.Name()
					songs = append(songs, Song{ID: fileID(c.profile.ID, path), ProfileID: c.profile.ID, Title: strings.TrimSuffix(name, filepath.Ext(name)), Album: filepath.Base(filepath.Dir(path)), Path: path, Codec: strings.TrimPrefix(filepath.Ext(name), ".")})
				}
			}
		}
		return nil
	})
	sortedSongs(songs)
	return songs, err
}

// downloadPath 将缓存限制在应用数据目录内，不接受前端指定路径。
func (s *Service) downloadPath(song Song) string {
	sum := sha256.Sum256([]byte(song.ID))
	ext := filepath.Ext(song.Path)
	if !audioFile("file" + ext) {
		ext = ".audio"
	}
	return filepath.Join(s.dir, "Downloads", hex.EncodeToString(sum[:])+ext)
}

// Download 将授权音乐保存到应用缓存，使用临时文件防止中断后留下损坏文件。
func (s *Service) Download(id string) error {
	s.mu.Lock()
	song, ok := s.songs[id]
	s.mu.Unlock()
	if !ok {
		return errors.New("song not found")
	}
	if song.ProfileID == "local" || song.ProfileID == "radio" {
		return errors.New("this item cannot be downloaded")
	}
	target := s.downloadPath(song)
	if _, err := os.Stat(target); err == nil {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
		return err
	}
	temp, err := os.CreateTemp(filepath.Dir(target), "pending-*")
	if err != nil {
		return err
	}
	defer os.Remove(temp.Name())
	var reader io.ReadCloser
	if song.ProfileID == "podcast" {
		resp, err := http.Get(song.Path)
		if err != nil {
			temp.Close()
			return err
		}
		if resp.StatusCode != 200 {
			resp.Body.Close()
			temp.Close()
			return fmt.Errorf("HTTP %d", resp.StatusCode)
		}
		reader = resp.Body
	} else {
		c, err := s.client(song.ProfileID)
		if err != nil {
			temp.Close()
			return err
		}
		if c.profile.Provider == "smb" {
			err = c.withSMB(func(share *smb2.Share) error {
				file, err := share.Open(song.Path)
				if err != nil {
					return err
				}
				defer file.Close()
				_, err = io.Copy(temp, file)
				return err
			})
			temp.Close()
			if err != nil {
				return err
			}
			if err := os.Rename(temp.Name(), target); err != nil {
				return err
			}
			return s.rememberDownload(song)
		}
		req, err := c.request("GET", c.mediaAddress(song, false), nil)
		if err != nil {
			temp.Close()
			return err
		}
		resp, err := c.http.Do(req)
		if err != nil {
			temp.Close()
			return errors.New("download connection failed")
		}
		if resp.StatusCode != 200 {
			resp.Body.Close()
			temp.Close()
			return fmt.Errorf("HTTP %d", resp.StatusCode)
		}
		reader = resp.Body
	}
	defer reader.Close()
	_, err = io.Copy(temp, reader)
	closeErr := temp.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err := os.Rename(temp.Name(), target); err != nil {
		return err
	}
	return s.rememberDownload(song)
}

// Downloads 列出已完整缓存的歌曲。
func (s *Service) Downloads() []Song {
	s.mu.Lock()
	defer s.mu.Unlock()
	songs := []Song{}
	for _, song := range s.songs {
		if _, err := os.Stat(s.downloadPath(song)); err == nil {
			songs = append(songs, song)
		}
	}
	sortedSongs(songs)
	return songs
}

// RemoveDownload 仅移除应用自己的缓存，不删除原始文件。
func (s *Service) RemoveDownload(id string) error {
	s.mu.Lock()
	song, ok := s.songs[id]
	s.mu.Unlock()
	if !ok {
		return errors.New("song not found")
	}
	return os.Remove(s.downloadPath(song))
}

// serveMedia 为系统 WebView 提供已登记条目的媒体与封面，支持 Range 请求。
func (s *Service) serveMedia(w http.ResponseWriter, r *http.Request) {
	parts := strings.SplitN(strings.TrimPrefix(r.URL.Path, "/"), "/", 2)
	if len(parts) != 2 {
		http.NotFound(w, r)
		return
	}
	id, err := url.PathUnescape(parts[1])
	if err != nil {
		http.NotFound(w, r)
		return
	}
	s.mu.Lock()
	song, ok := s.songs[id]
	s.mu.Unlock()
	if !ok {
		http.NotFound(w, r)
		return
	}
	artwork := parts[0] == "artwork"
	origin := r.Header.Get("Origin")
	allowed := map[string]bool{"mygo://localhost": true, "http://localhost:5173": true, "http://127.0.0.1:5173": true}
	if origin != "" && !allowed[origin] {
		http.Error(w, "origin not allowed", http.StatusForbidden)
		return
	}
	if origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
	}
	if song.ProfileID == "local" {
		if artwork {
			f, err := os.Open(song.Path)
			if err != nil {
				http.NotFound(w, r)
				return
			}
			defer f.Close()
			metadata, err := tag.ReadFrom(f)
			if err != nil || metadata.Picture() == nil {
				http.NotFound(w, r)
				return
			}
			pic := metadata.Picture()
			w.Header().Set("Content-Type", pic.MIMEType)
			w.Write(pic.Data)
			return
		}
		http.ServeFile(w, r, song.Path)
		return
	}
	if !artwork {
		if _, err := os.Stat(s.downloadPath(song)); err == nil {
			http.ServeFile(w, r, s.downloadPath(song))
			return
		}
	}
	address := song.Path
	streamTransport := http.DefaultTransport.(*http.Transport).Clone()
	streamTransport.ResponseHeaderTimeout = 20 * time.Second
	client := &http.Client{Transport: streamTransport}
	var req *http.Request
	if song.ProfileID == "radio" || song.ProfileID == "podcast" {
		if artwork {
			address = song.Artwork
		}
		req, err = http.NewRequestWithContext(r.Context(), "GET", address, nil)
	} else {
		c, e := s.client(song.ProfileID)
		if e != nil {
			http.Error(w, "server unavailable", 503)
			return
		}
		if c.profile.Provider == "smb" {
			if artwork {
				http.NotFound(w, r)
				return
			}
			if err = s.Download(id); err != nil {
				http.Error(w, "SMB stream unavailable", 502)
				return
			}
			http.ServeFile(w, r, s.downloadPath(song))
			return
		}
		address = c.mediaAddress(song, artwork)
		if address == "" {
			http.NotFound(w, r)
			return
		}
		req, err = c.request("GET", address, nil)
		if req != nil {
			req = req.WithContext(r.Context())
		}
		streamClient := *c.http
		streamClient.Timeout = 0
		client = &streamClient
	}
	if err != nil {
		http.Error(w, "media unavailable", 502)
		return
	}
	if rangeHeader := r.Header.Get("Range"); rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, "media unavailable", 502)
		return
	}
	defer resp.Body.Close()
	for _, header := range []string{"Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Cache-Control"} {
		if v := resp.Header.Get(header); v != "" {
			w.Header().Set(header, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

// rememberDownload 保存已下载条目快照，让离线资料跨启动可用。
func (s *Service) rememberDownload(song Song) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, cached := range s.state.Cached {
		if cached.ID == song.ID {
			return nil
		}
	}
	s.state.Cached = append(s.state.Cached, song)
	return s.saveLocked()
}
