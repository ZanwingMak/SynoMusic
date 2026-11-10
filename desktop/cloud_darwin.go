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
var nativeRestoreFiles func()
var nativeSupportDirectory func(uintptr)
var nativeRememberFiles func(string) int32
var nativeCloudCallback uintptr
var nativeCloudResult = make(chan string, 16)

// loadNativeBridge 装入 Swift 桥接库，让 CloudKit 和沙盒文件访问沿用主应用身份。
func loadNativeBridge() error {
	if nativeCloudCall != nil {
		return nil
	}
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	paths := []string{filepath.Join(filepath.Dir(executable), "../Resources/native/libSynoMusicCloud.dylib"), "resources/native/libSynoMusicCloud.dylib"}
	var handle uintptr
	var firstLoadError error
	for _, path := range paths {
		handle, err = purego.Dlopen(path, purego.RTLD_NOW|purego.RTLD_LOCAL)
		if err == nil {
			break
		}
		if firstLoadError == nil {
			firstLoadError = err
		}
	}
	if err != nil {
		return errors.Join(errors.New("Mac native bridge is unavailable"), firstLoadError)
	}
	purego.RegisterLibFunc(&nativeCloudCall, handle, "synomusic_cloud_sync")
	purego.RegisterLibFunc(&nativeRestoreFiles, handle, "synomusic_restore_files")
	purego.RegisterLibFunc(&nativeSupportDirectory, handle, "synomusic_support_directory")
	purego.RegisterLibFunc(&nativeRememberFiles, handle, "synomusic_remember_files")
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
	if err := loadNativeBridge(); err != nil {
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

// restoreLocalAccess 在启动时恢复用户选择过的目录权限，不把书签同步到云端。
func restoreLocalAccess() {
	nativeCloudMu.Lock()
	defer nativeCloudMu.Unlock()
	if loadNativeBridge() == nil {
		nativeRestoreFiles()
	}
}

// rememberLocalAccess 为本次原生选择的目录保留沙盒访问权限。
func rememberLocalAccess(paths []string) error {
	nativeCloudMu.Lock()
	defer nativeCloudMu.Unlock()
	if err := loadNativeBridge(); err != nil {
		return err
	}
	data, err := json.Marshal(paths)
	if err != nil {
		return err
	}
	if nativeRememberFiles(string(data)) != 0 {
		return errors.New("could not retain folder access; select the folder again")
	}
	return nil
}

// desktopConfigDir 使用 Foundation 解析容器内目录，兼容从终端启动的沙盒应用。
func desktopConfigDir() (string, error) {
	nativeCloudMu.Lock()
	defer nativeCloudMu.Unlock()
	if err := loadNativeBridge(); err != nil {
		return "", err
	}
	var path string
	callback := purego.NewCallback(func(pointer *byte) {
		if pointer == nil {
			return
		}
		length := 0
		for length < 32768 && *(*byte)(unsafe.Add(unsafe.Pointer(pointer), length)) != 0 {
			length++
		}
		path = string(unsafe.Slice(pointer, length))
	})
	nativeSupportDirectory(callback)
	if path == "" {
		return "", errors.New("application support directory is unavailable")
	}
	return path, nil
}
