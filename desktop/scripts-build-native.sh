#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 编译两种 Mac 架构并合成原生 CloudKit 桥接库，保持 MyGo 主进程承载原生身份。
build_native_bridge() {
  mkdir -p ../build/MacNative
  xcrun swiftc -swift-version 5 -emit-library -O -target arm64-apple-macos13.0 resources/native/CloudBridge.swift -o ../build/MacNative/cloud-arm64.dylib -framework CloudKit
  xcrun swiftc -swift-version 5 -emit-library -O -target x86_64-apple-macos13.0 resources/native/CloudBridge.swift -o ../build/MacNative/cloud-x86_64.dylib -framework CloudKit
  xcrun lipo -create ../build/MacNative/cloud-arm64.dylib ../build/MacNative/cloud-x86_64.dylib -output resources/native/libSynoMusicCloud.dylib
}

build_native_bridge
