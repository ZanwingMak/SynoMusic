package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"github.com/ebitengine/purego"
)

var nativeCloudMu sync.Mutex
var nativeCloudCall func(string, uintptr)
var nativeCloudCallback uintptr
var nativeCloudResult = make(chan string, 16)

// loadNativeCloud 将 Swift 桥接动态库装入主进程，沿用签名应用的 CloudKit 身份。
func loadNativeCloud() error {
	if nativeCloudCall != nil {
		return nil
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	paths := []string{filepath.Join(filepath.Dir(executable), "../Resources/native/libSynoMusicCloud.dylib"), "resources/native/libSynoMusicCloud.dylib"}
	var handle uintptr
	for _, path := range paths {
		handle, err = purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
		if err == nil {
			break
		}
	}
	if err != nil {
		return errors.New("iCloud requires the signed Mac application")
	}
	purego.RegisterLibFunc(&nativeCloudCall, handle, "synomusic_cloud_sync")
	nativeCloudCallback = purego.NewCallback(func(pointer *byte) {
		if pointer == nil {
			return
		}
		length := 0
		for length < 32<<20 && *(*byte)(unsafe.Add(unsafe.Pointer(pointer), length)) != 0 {
			length++
		}
		value := string(unsafe.Slice(pointer, length))
		select {
		case nativeCloudResult <- value:
		default:
		}
	})
	return nil
}

// syncNativeCloud 序列化跨语言调用，不将密码或本地音乐文件上传到云端。
func syncNativeCloud(state []byte, updatedAt int64) ([]byte, int64, error) {
	nativeCloudMu.Lock()
	defer nativeCloudMu.Unlock()
	if err := loadNativeCloud(); err != nil {
		return nil, 0, err
	}
	requestID := newID()
	input, _ := json.Marshal(map[string]any{"requestID": requestID, "operation": "sync", "state": state, "updatedAt": float64(updatedAt) / 1000})
	nativeCloudCall(string(input), nativeCloudCallback)
	timeout := time.NewTimer(45 * time.Second)
	defer timeout.Stop()
	for {
		select {
		case raw := <-nativeCloudResult:
			var reply struct {
				RequestID string  `json:"requestID"`
				State     []byte  `json:"state"`
				UpdatedAt float64 `json:"updatedAt"`
				Error     string  `json:"error"`
			}
			if err := json.Unmarshal([]byte(raw), &reply); err != nil {
				return nil, 0, err
			}
			if reply.RequestID != requestID {
				continue
			}
			if reply.Error != "" {
				return nil, 0, errors.New(reply.Error)
			}
			return reply.State, int64(reply.UpdatedAt * 1000), nil
		case <-timeout.C:
			return nil, 0, errors.New("iCloud sync timed out")
		}
	}
}
