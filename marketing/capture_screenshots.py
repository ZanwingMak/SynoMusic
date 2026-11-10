#!/usr/bin/env python3
"""使用真实 iOS 模拟器生成各语言的应用截图。"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'app.synomusic.SynoMusic'
LANGUAGES = {'en-US': 'en', 'zh-Hans': 'zh-Hans', 'zh-Hant': 'zh-Hant', 'ja': 'ja', 'ko': 'ko', 'de-DE': 'de', 'fr-FR': 'fr'}
PAGES = {'library': [], 'browse': ['-browse'], 'player': ['-fullplayer', '-lyrics'], 'settings': ['-settings'], 'support': ['-support']}


def command(*args, check=True):
    """运行模拟器命令，失败时保留可定位问题的错误。"""
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)


def capture_device(device, platform, app_path, locales):
    """在单个隔离设备中顺序启动真实页面并截取完整屏幕。"""
    command('install', device, str(app_path))
    command('status_bar', device, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
    command('ui', device, 'appearance', 'light')
    for locale in locales:
        language = LANGUAGES[locale]
        output = ROOT / 'build' / 'Marketing' / 'raw' / locale
        output.mkdir(parents=True, exist_ok=True)
        for page, flags in PAGES.items():
            command('terminate', device, BUNDLE, check=False)
            command('launch', device, BUNDLE, '-demo', '-AppleLanguages', f'({language})', '-syno.language', language, *flags)
            # 等待启动动画、异步资料加载及真实 StoreKit 商品响应。
            time.sleep(7 if page == 'support' else 3)
            target = output / f'{platform}-{page}.png'
            command('io', device, 'screenshot', str(target))
            print(f'{platform}: {locale}/{page}', flush=True)


def main():
    """接收已启动的隔离模拟器，分别采集 iPhone 与 iPad 的七语言页面。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--iphone', required=True)
    parser.add_argument('--ipad')
    parser.add_argument('--locale', choices=LANGUAGES)
    args = parser.parse_args()
    app_path = ROOT / 'build/FreeFeaturesSimulator/Build/Products/Debug-iphonesimulator/SynoMusic.app'
    if not app_path.is_dir():
        raise SystemExit('请先编译 iOS Simulator Debug 应用。')
    locales = [args.locale] if args.locale else list(LANGUAGES)
    devices = [(args.iphone, 'iphone')]
    if args.ipad:
        devices.append((args.ipad, 'ipad'))
    with ThreadPoolExecutor(max_workers=len(devices)) as executor:
        futures = [executor.submit(capture_device, device, platform, app_path, locales) for device, platform in devices]
        for future in futures:
            future.result()


if __name__ == '__main__':
    main()
