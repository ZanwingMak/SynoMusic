//go:build !darwin

package main

import "errors"

// syncNativeCloud 明确说明 iCloud 原生能力仅支持 macOS。
func syncNativeCloud(state []byte, updatedAt int64) ([]byte, int64, error) {
	return nil, 0, errors.New("iCloud sync is available on macOS")
}
