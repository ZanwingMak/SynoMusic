package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// libraryClient 封装音乐源会话；所有凭证仅存在 Go 层。
type libraryClient struct {
	mu       sync.Mutex
	profile  Profile
	http     *http.Client
	token    string
	userID   string
	password string
	base     string
}

// connectLibrary 验证服务器连接，并按音乐源协议建立会话。
func connectLibrary(p Profile, password, otp string) (*libraryClient, error) {
	if p.Provider == "smb" {
		return connectSMB(p, password)
	}
	if p.IsQuickConnect || p.QuickConnectID != "" {
		base, err := resolveQuickConnect(p.QuickConnectID)
		if err != nil {
			return nil, err
		}
		u, _ := url.Parse(base)
		p.Host = u.Hostname()
		p.Scheme = u.Scheme
		p.Port, _ = strconv.Atoi(u.Port())
	}
	host := strings.TrimSpace(p.Host)
	if net.ParseIP(host) != nil {
		host = "[" + host + "]"
	}
	if !strings.Contains(host, "://") {
		scheme := p.Scheme
		if scheme == "" {
			scheme = "https"
		}
		host = scheme + "://" + host
	}
	u, err := url.Parse(host)
	if err != nil || u.Hostname() == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return nil, errors.New("invalid HTTP(S) server address")
	}
	if p.Port > 0 && u.Port() == "" {
		u.Host = net.JoinHostPort(u.Hostname(), strconv.Itoa(p.Port))
	}
	if u.Path != "" && u.Path != "/" {
		p.BasePath = strings.TrimRight(u.Path, "/")
	} else if p.BasePath != "" {
		u.Path = p.BasePath
	}
	p.Scheme = u.Scheme
	p.Host = u.Hostname()
	p.Port, _ = strconv.Atoi(u.Port())
	if p.Port == 0 {
		if p.Scheme == "https" {
			p.Port = 443
		} else {
			p.Port = 80
		}
	}
	if p.Provider == "webDAV" {
		if u.Path != "" && u.Path != "/" {
			p.LibraryID = u.Path
		} else if p.LibraryID != "" {
			u.Path = "/" + strings.Trim(p.LibraryID, "/")
		}
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	if p.IgnoreInvalidCertificate {
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
	} // 用户明确选择信任自签名证书。
	c := &libraryClient{profile: p, http: &http.Client{Timeout: 45 * time.Second, Transport: transport}, password: password, base: strings.TrimRight(u.String(), "/")}
	transport.ResponseHeaderTimeout = 25 * time.Second
	c.http.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if len(via) > 0 && via[0].URL.Scheme == "https" && req.URL.Scheme == "http" {
			return errors.New("HTTPS downgrade is not allowed")
		}
		if len(via) >= 6 {
			return errors.New("too many redirects")
		}
		if req.URL.Host != via[0].URL.Host || req.URL.Scheme != via[0].URL.Scheme {
			req.Header.Del("X-Emby-Token")
			req.Header.Del("X-Plex-Token")
			req.Header.Del("Authorization")
		}
		return nil
	}
	switch p.Provider {
	case "synologyAudioStation":
		params := url.Values{"api": {"SYNO.API.Auth"}, "method": {"Login"}, "version": {"6"}, "account": {p.Username}, "passwd": {password}, "session": {"AudioStation"}, "format": {"sid"}}
		if otp != "" {
			params.Set("otp_code", otp)
		}
		data, err := c.jsonRequest("POST", "/webapi/entry.cgi", nil, params)
		if err != nil {
			return nil, err
		}
		if !boolean(data["success"]) {
			return nil, errors.New("Audio Station login failed; check account, permissions and OTP")
		}
		c.token = str(obj(data["data"])["sid"])
	case "jellyfin", "emby":
		data, err := c.jsonRequest("POST", "/Users/AuthenticateByName", nil, map[string]any{"Username": p.Username, "Pw": password})
		if err != nil {
			return nil, err
		}
		c.token = str(data["AccessToken"])
		c.userID = str(obj(data["User"])["Id"])
		if c.token == "" || c.userID == "" {
			return nil, errors.New("server authentication failed")
		}
	case "plex":
		c.token = password
		if _, err := c.jsonRequest("GET", "/identity", nil, nil); err != nil {
			return nil, errors.New("Plex connection failed; use your Plex access token as the password")
		}
	case "webDAV":
		if _, err := c.webDAVEntries(c.base + "/"); err != nil {
			return nil, err
		}
	default:
		return nil, errors.New("unsupported music provider")
	}
	return c, nil
}

// request 为同源请求补齐授权信息，保持跨源公开媒体请求不携带 NAS 凭证。
func (c *libraryClient) request(method, address string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequest(method, address, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "SynoMusic/1.6.0 ("+runtime.GOOS+")")
	base, _ := url.Parse(c.base)
	if req.URL.Host == base.Host && req.URL.Scheme == base.Scheme {
		switch c.profile.Provider {
		case "jellyfin", "emby":
			req.Header.Set("X-Emby-Authorization", `MediaBrowser Client="SynoMusic", Device="Desktop", DeviceId="synomusic-desktop", Version="1.6.3"`)
			if c.token != "" {
				req.Header.Set("X-Emby-Token", c.token)
			}
		case "plex":
			req.Header.Set("X-Plex-Token", c.token)
			req.Header.Set("X-Plex-Client-Identifier", "app.synomusic.SynoMusic.desktop")
			req.Header.Set("Accept", "application/json")
		case "webDAV":
			req.SetBasicAuth(c.profile.Username, c.password)
		}
	}
	return req, nil
}

// sessionToken 安全读取会话令牌，避免并发封面请求与重新认证互相覆盖。
func (c *libraryClient) sessionToken() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.token
}

// renewSession 仅刷新仍然过期的 Audio Station 会话，避免并发请求重复登录。
func (c *libraryClient) renewSession(expired string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.token != expired {
		return nil
	}
	updated, err := connectLibrary(c.profile, c.password, "")
	if err != nil {
		return err
	}
	c.token = updated.token
	return nil
}

// jsonRequest 在 Audio Station 会话过期时透明重试一次，其余错误保留原响应。
func (c *libraryClient) jsonRequest(method, path string, params url.Values, payload any) (map[string]any, error) {
	result, err := c.doJSONRequest(method, path, params, payload)
	code := int(number(obj(result["error"])["code"]))
	if err == nil && c.profile.Provider == "synologyAudioStation" && params.Get("_sid") != "" && (code == 106 || code == 107) {
		if err = c.renewSession(params.Get("_sid")); err != nil {
			return nil, err
		}
		retry := url.Values{}
		for key, values := range params {
			retry[key] = append([]string{}, values...)
		}
		retry.Set("_sid", c.sessionToken())
		return c.doJSONRequest(method, path, retry, payload)
	}
	return result, err
}

// doJSONRequest 执行有大小限制的 JSON 或表单请求并检查 HTTP 状态。
func (c *libraryClient) doJSONRequest(method, path string, params url.Values, payload any) (map[string]any, error) {
	address := c.base + path
	if len(params) > 0 {
		address += "?" + params.Encode()
	}
	var body io.Reader
	contentType := "application/json"
	if form, ok := payload.(url.Values); ok {
		body = strings.NewReader(form.Encode())
		contentType = "application/x-www-form-urlencoded"
	} else if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(data)
	}
	req, err := c.request(method, address, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", contentType)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, errors.New("cannot connect to the music server")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("music server returned HTTP %d", resp.StatusCode)
	}
	var result map[string]any
	err = json.NewDecoder(io.LimitReader(resp.Body, 32<<20)).Decode(&result)
	return result, err
}

// openMedia 保留流式传输与 Range，遇到过期的 Audio Station 会话时重新认证一次。
func (c *libraryClient) openMedia(ctx context.Context, song Song, artwork bool, byteRange string) (*http.Response, error) {
	client := *c.http
	client.Timeout = 0
	for attempt := 0; attempt < 2; attempt++ {
		token := c.sessionToken()
		req, err := c.request("GET", c.mediaAddress(song, artwork), nil)
		if err != nil {
			return nil, err
		}
		req = req.WithContext(ctx)
		if byteRange != "" {
			req.Header.Set("Range", byteRange)
		}
		response, err := client.Do(req)
		if err != nil {
			return nil, errors.New("media connection failed")
		}
		if c.profile.Provider != "synologyAudioStation" || !strings.Contains(response.Header.Get("Content-Type"), "application/json") {
			return response, nil
		}
		var payload map[string]any
		_ = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&payload)
		response.Body.Close()
		code := int(number(obj(payload["error"])["code"]))
		if attempt == 0 && (code == 106 || code == 107) {
			if err = c.renewSession(token); err != nil {
				return nil, err
			}
			continue
		}
		return nil, fmt.Errorf("Audio Station media error %d", code)
	}
	return nil, errors.New("media session expired")
}

// loadSongs 分页拉取完整音乐库，避免只显示首批歌曲。
func (c *libraryClient) loadSongs() ([]Song, error) {
	switch c.profile.Provider {
	case "webDAV":
		return c.scanWebDAV()
	case "smb":
		return c.scanSMB()
	}
	songs := []Song{}
	seen := map[string]bool{}
	const pageSize = 500
	for offset := 0; ; offset += pageSize {
		var items []any
		switch c.profile.Provider {
		case "synologyAudioStation":
			q := url.Values{"api": {"SYNO.AudioStation.Song"}, "version": {"3"}, "method": {"list"}, "library": {"shared"}, "limit": {strconv.Itoa(pageSize)}, "offset": {strconv.Itoa(offset)}, "sort_by": {"title"}, "sort_direction": {"ASC"}, "additional": {"song_tag,song_audio,song_rating"}, "_sid": {c.sessionToken()}}
			data, err := c.jsonRequest("GET", "/webapi/AudioStation/song.cgi", q, nil)
			if err != nil {
				return nil, err
			}
			if !boolean(data["success"]) {
				return nil, errors.New("Audio Station library request failed")
			}
			items = arr(obj(data["data"])["songs"])
		case "jellyfin", "emby":
			q := url.Values{"IncludeItemTypes": {"Audio"}, "Recursive": {"true"}, "Fields": {"MediaSources,Genres,Path"}, "Limit": {strconv.Itoa(pageSize)}, "StartIndex": {strconv.Itoa(offset)}, "SortBy": {"SortName"}, "UserId": {c.userID}}
			if c.profile.LibraryID != "" {
				q.Set("ParentId", c.profile.LibraryID)
			}
			data, err := c.jsonRequest("GET", "/Users/"+url.PathEscape(c.userID)+"/Items", q, nil)
			if err != nil {
				return nil, err
			}
			items = arr(data["Items"])
		case "plex":
			library := c.profile.LibraryID
			if library == "" {
				data, err := c.jsonRequest("GET", "/library/sections", nil, nil)
				if err != nil {
					return nil, err
				}
				for _, item := range arr(obj(data["MediaContainer"])["Directory"]) {
					v := obj(item)
					if str(v["type"]) == "artist" {
						library = str(v["key"])
						break
					}
				}
				if library == "" {
					return nil, errors.New("no Plex music library found")
				}
			}
			q := url.Values{"type": {"10"}, "X-Plex-Container-Start": {strconv.Itoa(offset)}, "X-Plex-Container-Size": {strconv.Itoa(pageSize)}}
			data, err := c.jsonRequest("GET", "/library/sections/"+url.PathEscape(library)+"/all", q, nil)
			if err != nil {
				return nil, err
			}
			items = arr(obj(data["MediaContainer"])["Metadata"])
		}
		added := 0
		for _, raw := range items {
			song := c.mapSong(obj(raw))
			if song.ID != "" && !seen[song.ID] {
				seen[song.ID] = true
				songs = append(songs, song)
				added++
			}
		}
		if len(items) < pageSize || added == 0 {
			break
		}
	}
	sortedSongs(songs)
	return songs, nil
}

// mapSong 将不同服务器的原始对象转换为同一歌曲模型。
func (c *libraryClient) mapSong(v map[string]any) Song {
	song := Song{ProfileID: c.profile.ID}
	switch c.profile.Provider {
	case "synologyAudioStation":
		additional := obj(v["additional"])
		tag := obj(additional["song_tag"])
		audio := obj(additional["song_audio"])
		song.ID = c.profile.ID + ":" + str(v["id"])
		song.Path = str(v["id"])
		song.Title = str(v["title"])
		song.Artist = str(tag["artist"])
		song.AlbumArtist = str(tag["album_artist"])
		song.Year = int(number(tag["year"]))
		song.Disc = int(number(tag["disc"]))
		song.Bitrate = int(number(audio["bitrate"]))
		song.SampleRate = int(number(audio["frequency"]))
		song.Album = str(tag["album"])
		song.Genre = str(tag["genre"])
		song.Track = int(number(tag["track"]))
		song.Duration = number(audio["duration"])
		song.Codec = str(audio["codec"])
	case "jellyfin", "emby":
		song.Path = str(v["Id"])
		song.ID = c.profile.ID + ":" + song.Path
		song.Title = str(v["Name"])
		artists := arr(v["Artists"])
		if len(artists) > 0 {
			song.Artist = str(artists[0])
		}
		song.Album = str(v["Album"])
		song.AlbumArtist = str(v["AlbumArtist"])
		song.Year = int(number(v["ProductionYear"]))
		song.Disc = int(number(v["ParentIndexNumber"]))
		song.Duration = number(v["RunTimeTicks"]) / 1e7
		song.Track = int(number(v["IndexNumber"]))
		genres := arr(v["Genres"])
		if len(genres) > 0 {
			song.Genre = str(genres[0])
		}
		sources := arr(v["MediaSources"])
		if len(sources) > 0 {
			song.Codec = str(obj(sources[0])["Container"])
		}
	case "plex":
		song.Path = str(v["ratingKey"])
		song.ID = c.profile.ID + ":" + song.Path
		song.Title = str(v["title"])
		song.Artist = str(v["grandparentTitle"])
		song.AlbumArtist = song.Artist
		song.Year = int(number(v["year"]))
		song.Disc = int(number(v["parentIndex"]))
		song.Album = str(v["parentTitle"])
		song.Duration = number(v["duration"]) / 1000
		song.Track = int(number(v["index"]))
		song.Artwork = str(v["parentThumb"])
		media := arr(v["Media"])
		if len(media) > 0 {
			m := obj(media[0])
			song.Codec = str(m["container"])
			parts := arr(m["Part"])
			if len(parts) > 0 {
				song.Path = str(obj(parts[0])["key"])
			}
		}
	}
	song.Artwork = "music://localhost/artwork/" + url.PathEscape(song.ID)
	return song
}

// mediaAddress 在需要播放时生成带会话授权的服务器地址。
func (c *libraryClient) mediaAddress(song Song, artwork bool) string {
	switch c.profile.Provider {
	case "synologyAudioStation":
		if artwork {
			return c.base + "/webapi/AudioStation/cover.cgi?" + url.Values{"api": {"SYNO.AudioStation.Cover"}, "method": {"getsongcover"}, "version": {"3"}, "id": {song.Path}, "_sid": {c.sessionToken()}}.Encode()
		}
		return c.base + "/webapi/AudioStation/stream.cgi?" + url.Values{"api": {"SYNO.AudioStation.Stream"}, "method": {"stream"}, "version": {"2"}, "id": {song.Path}, "_sid": {c.sessionToken()}}.Encode()
	case "jellyfin", "emby":
		if artwork {
			return c.base + "/Items/" + url.PathEscape(song.Path) + "/Images/Primary?maxWidth=600"
		}
		return c.base + "/Audio/" + url.PathEscape(song.Path) + "/stream?" + url.Values{"static": {"true"}, "UserId": {c.userID}}.Encode()
	case "plex":
		if artwork {
			return c.base + "/library/metadata/" + url.PathEscape(strings.TrimPrefix(song.ID, c.profile.ID+":")) + "/thumb"
		}
		return c.base + song.Path
	case "webDAV":
		if !artwork {
			return song.Path
		}
	}
	return ""
}

// resolveQuickConnect 解析用户明确填写的 QuickConnect ID，优先使用 HTTPS。
func resolveQuickConnect(id string) (string, error) {
	if strings.TrimSpace(id) == "" {
		return "", errors.New("QuickConnect ID is required")
	}
	endpoints := []string{"global.quickconnect.to", "cnc.quickconnect.cn", "euc.quickconnect.eu"}
	client := &http.Client{Timeout: 15 * time.Second}
	for _, endpoint := range endpoints {
		data, _ := json.Marshal(map[string]any{"command": "get_server_info", "id": "dsm_portal_https", "serverID": id, "version": 1, "stop_when_error": false, "stop_when_success": false})
		resp, err := client.Post("https://"+endpoint+"/Serv.php", "application/json", bytes.NewReader(data))
		if err != nil {
			continue
		}
		var result map[string]any
		err = json.NewDecoder(io.LimitReader(resp.Body, 2<<20)).Decode(&result)
		resp.Body.Close()
		if err != nil || number(result["errno"]) != 0 {
			continue
		}
		server := obj(result["server"])
		service := obj(result["service"])
		port := int(number(service["ext_port"]))
		if port == 0 {
			port = 5001
		}
		host := str(server["fqdn"])
		if host == "" {
			host = str(obj(server["external"])["ip"])
		}
		if host != "" {
			return "https://" + host + ":" + strconv.Itoa(port), nil
		}
	}
	return "", errors.New("QuickConnect could not resolve a direct address; enter a NAS or DDNS address")
}

// obj 安全读取可选 JSON 对象。
func obj(v any) map[string]any {
	m, _ := v.(map[string]any)
	if m == nil {
		return map[string]any{}
	}
	return m
}

// arr 安全读取可选 JSON 数组。
func arr(v any) []any { a, _ := v.([]any); return a }

// str 将服务器返回的字符串或数值标识符转换为字符串。
func str(v any) string {
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

// number 读取 JSON 数值，并兼容服务器返回的数值字符串。
func number(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case string:
		f, _ := strconv.ParseFloat(n, 64)
		return f
	}
	return 0
}

// boolean 安全读取 JSON 布尔值。
func boolean(v any) bool { b, _ := v.(bool); return b }
