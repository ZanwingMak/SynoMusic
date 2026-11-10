//go:build !darwin

package main

import (
	"errors"
	"os"
)

// syncNativeCloud 明确说明 iCloud 原生能力仅支持 macOS。
func syncNativeCloud(state []byte, updatedAt int64) ([]byte, int64, error) {
	return nil, 0, errors.New("iCloud sync is available on macOS")
}

// restoreLocalAccess 在无需沙盒书签的平台保留正常文件权限。
func restoreLocalAccess() {}

// rememberLocalAccess 在 Windows 直接使用原生文件选择器返回的路径。
func rememberLocalAccess(paths []string) error { return nil }

// desktopConfigDir 使用 Windows 当前用户的应用配置目录。
func desktopConfigDir() (string, error) { return os.UserConfigDir() }
