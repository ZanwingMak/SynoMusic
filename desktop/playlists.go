package main

import (
	"errors"
	"net/url"
	"strconv"
)

// RemotePlaylist 表示音乐服务器上的只读歌单，不修改用户的远端收藏。
type RemotePlaylist struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Count int    `json:"count"`
}

// ServerPlaylists 分页读取 Audio Station、Plex、Jellyfin 与 Emby 的音频歌单。
func (s *Service) ServerPlaylists(profileID string) ([]RemotePlaylist, error) {
	result := []RemotePlaylist{}
	if profileID == "local" {
		return result, nil
	}
	c, err := s.client(profileID)
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	for offset := 0; ; offset += 200 {
		var data map[string]any
		var items []any
		switch c.profile.Provider {
		case "synologyAudioStation":
			data, err = c.jsonRequest("GET", "/webapi/AudioStation/playlist.cgi", url.Values{"api": {"SYNO.AudioStation.Playlist"}, "version": {"3"}, "method": {"list"}, "library": {"all"}, "limit": {"200"}, "offset": {strconv.Itoa(offset)}, "additional": {"songs_total"}, "_sid": {c.sessionToken()}}, nil)
			if err == nil && !boolean(data["success"]) {
				err = errors.New("server playlist request failed")
			}
			items = arr(obj(data["data"])["playlists"])
		case "plex":
			data, err = c.jsonRequest("GET", "/playlists", url.Values{"playlistType": {"audio"}, "X-Plex-Container-Start": {strconv.Itoa(offset)}, "X-Plex-Container-Size": {"200"}}, nil)
			items = arr(obj(data["MediaContainer"])["Metadata"])
		case "jellyfin", "emby":
			data, err = c.jsonRequest("GET", "/Users/"+url.PathEscape(c.userID)+"/Items", url.Values{"IncludeItemTypes": {"Playlist"}, "MediaTypes": {"Audio"}, "Recursive": {"true"}, "UserId": {c.userID}, "Limit": {"200"}, "StartIndex": {strconv.Itoa(offset)}}, nil)
			items = arr(data["Items"])
		default:
			return result, nil
		}
		if err != nil {
			return nil, err
		}
		added := 0
		for _, raw := range items {
			item := obj(raw)
			entry := RemotePlaylist{}
			switch c.profile.Provider {
			case "synologyAudioStation":
				entry = RemotePlaylist{str(item["id"]), str(item["name"]), int(number(obj(item["additional"])["songs_total"]))}
			case "plex":
				entry = RemotePlaylist{str(item["ratingKey"]), str(item["title"]), int(number(item["leafCount"]))}
			default:
				entry = RemotePlaylist{str(item["Id"]), str(item["Name"]), int(number(item["ChildCount"]))}
			}
			if entry.ID != "" && !seen[entry.ID] {
				result = append(result, entry)
				seen[entry.ID] = true
				added++
			}
		}
		if len(items) < 200 || added == 0 {
			return result, nil
		}
	}
}

// ServerPlaylistSongs 读取全部歌单分页，并登记供原生媒体代理播放的歌曲快照。
func (s *Service) ServerPlaylistSongs(profileID, playlistID string) ([]Song, error) {
	c, err := s.client(profileID)
	if err != nil {
		return nil, err
	}
	songs := []Song{}
	seen := map[string]bool{}
	for offset := 0; ; offset += 200 {
		var data map[string]any
		var items []any
		switch c.profile.Provider {
		case "synologyAudioStation":
			data, err = c.jsonRequest("GET", "/webapi/AudioStation/playlist.cgi", url.Values{"api": {"SYNO.AudioStation.Playlist"}, "version": {"3"}, "method": {"getinfo"}, "id": {playlistID}, "library": {"all"}, "songs_offset": {strconv.Itoa(offset)}, "songs_limit": {"200"}, "additional": {"songs,songs_song_tag,songs_song_audio"}, "_sid": {c.sessionToken()}}, nil)
			if err == nil && !boolean(data["success"]) {
				err = errors.New("server playlist request failed")
			}
			lists := arr(obj(data["data"])["playlists"])
			if len(lists) > 0 {
				items = arr(obj(obj(lists[0])["additional"])["songs"])
			}
		case "plex":
			data, err = c.jsonRequest("GET", "/playlists/"+url.PathEscape(playlistID)+"/items", url.Values{"X-Plex-Container-Start": {strconv.Itoa(offset)}, "X-Plex-Container-Size": {"200"}}, nil)
			items = arr(obj(data["MediaContainer"])["Metadata"])
		case "jellyfin", "emby":
			data, err = c.jsonRequest("GET", "/Users/"+url.PathEscape(c.userID)+"/Items", url.Values{"ParentId": {playlistID}, "IncludeItemTypes": {"Audio"}, "Recursive": {"true"}, "Fields": {"MediaSources,Genres,Path"}, "Limit": {"200"}, "StartIndex": {strconv.Itoa(offset)}}, nil)
			items = arr(data["Items"])
		default:
			return nil, errors.New("this source does not provide server playlists")
		}
		if err != nil {
			return nil, err
		}
		added := 0
		for _, raw := range items {
			song := c.mapSong(obj(raw))
			if song.ID != "" && !seen[song.ID] {
				songs = append(songs, song)
				seen[song.ID] = true
				added++
			}
		}
		if len(items) < 200 || added == 0 {
			break
		}
	}
	s.mu.Lock()
	for _, song := range songs {
		s.songs[song.ID] = song
	}
	s.mu.Unlock()
	return songs, nil
}
