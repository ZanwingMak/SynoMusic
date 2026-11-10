#!/usr/bin/env python3
"""用真实客户端截图生成多语言商店图片及宣传图。"""
from __future__ import annotations

import argparse
from functools import lru_cache
from io import BytesIO
import json
from pathlib import Path
import subprocess
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(__file__).resolve().parent
PAPER = "#f2f0e9"
INK = "#262724"
MUTED = "#777971"
ACCENT = "#b65d48"
PAGES = ("library", "browse", "player", "settings")
CANONICAL = {"en": "en-US", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
             "ja": "ja", "ko": "ko", "de": "de-DE", "fr": "fr-FR"}


# 返回各语言适用的系统字体，避免中文、日文、韩文显示为缺字方框。
@lru_cache(maxsize=32)
def font_spec(locale: str) -> tuple[str, int]:
    fonts = Path("/System/Library/Fonts")
    if locale.startswith("zh"):
        return str(fonts / "Hiragino Sans GB.ttc"), 2
    if locale == "ja":
        return str(next(fonts.glob("*W6.ttc"))), 0
    if locale == "ko":
        return str(fonts / "AppleSDGothicNeo.ttc"), 6
    return str(fonts / "Supplemental/Arial Bold.ttf"), 0


# 缓存不同字号的字体对象，减少批量渲染开销。
@lru_cache(maxsize=128)
def font(locale: str, size: int) -> ImageFont.FreeTypeFont:
    path, index = font_spec(locale)
    return ImageFont.truetype(path, size, index=index)


# 编译仅负责阿拉伯排版的本机辅助程序，不依赖网络字体或额外 Python 排版库。
def text_renderer(output: Path) -> Path:
    source = SOURCE / "render_text.swift"
    binary = output / ".cache/render-text"
    if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
        binary.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", str(source),
                        "-o", str(binary)], check=True)
    return binary


# 用 macOS 原生文字引擎渲染阿拉伯连写及混合方向文字。
def arabic_layer(text: str, size: int, width: int, color: str,
                 spacing: int, output: Path) -> Image.Image:
    request = {"text": text, "size": size, "width": width, "color": color,
               "lineSpacing": spacing, "rightToLeft": True}
    result = subprocess.run([str(text_renderer(output))],
                            input=json.dumps(request, ensure_ascii=False).encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return Image.open(BytesIO(result.stdout)).convert("RGBA")


# 在指定宽度内缩放标题字号，保留人工安排的换行。
def fit_font(text: str, locale: str, size: int, width: int) -> ImageFont.FreeTypeFont:
    chosen = font(locale, size)
    while size > 22 and max(chosen.getlength(line) for line in text.splitlines()) > width:
        size -= 2
        chosen = font(locale, size)
    return chosen


# 将本地化标题排成透明图层，阿拉伯文使用原生 RTL 排版。
def headline_layer(text: str, locale: str, size: int, width: int,
                   color: str, output: Path) -> Image.Image:
    spacing = max(8, size // 8)
    if locale == "ar-SA":
        return arabic_layer(text, size, width, color, spacing, output)
    chosen = fit_font(text, locale, size, width)
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    bounds = probe.multiline_textbbox((0, 0), text, font=chosen, spacing=spacing)
    padding = max(6, chosen.size // 12)
    layer = Image.new("RGBA", (width, int(bounds[3] - bounds[1]) + padding * 2))
    ImageDraw.Draw(layer).multiline_text(
        (padding - bounds[0], padding - bounds[1]), text, font=chosen,
        fill=color, spacing=spacing, stroke_width=0
    )
    return layer


# 绘制可重复使用的品牌行，波形为脚本原创图形。
def draw_brand(image: Image.Image, x: int, y: int, scale: float = 1) -> None:
    draw = ImageDraw.Draw(image)
    mark = int(42 * scale)
    draw.rounded_rectangle((x, y, x + mark, y + mark), radius=int(12 * scale), fill=ACCENT)
    widths = [10, 20, 28, 16]
    for index, height in enumerate(widths):
        center = x + int((12 + index * 6) * scale)
        top = y + (mark - int(height * scale)) // 2
        draw.line((center, top, center, top + int(height * scale)),
                  fill="#fffaf3", width=max(2, int(2 * scale)))
    draw.text((x + mark + int(14 * scale), y + int(7 * scale)), "SynoMusic",
              font=font("en-US", int(30 * scale)), fill=INK)


# 绘制淡色原创唱片线条，为截图保留清晰的主体层级。
def draw_record(image: Image.Image, center: tuple[int, int], radius: int) -> None:
    draw = ImageDraw.Draw(image)
    x, y = center
    for distance in range(radius // 4, radius, max(10, radius // 8)):
        draw.ellipse((x - distance, y - distance, x + distance, y + distance),
                     outline="#dedbd1", width=2)
    hole = max(4, radius // 25)
    draw.ellipse((x - hole, y - hole, x + hole, y + hole), fill="#d4c2ad")


# 从对应区域、应用 UI 语言和英语后备中选取真实截图。
def find_raw(raw: Path, locale: str, metadata: dict, filename: str) -> Path | None:
    candidates = [locale, CANONICAL.get(metadata["uiLanguage"], "en-US"), "en-US"]
    for candidate in dict.fromkeys(candidates):
        path = raw / candidate / filename
        if path.is_file():
            return path
    return None


# 将整张原始截图按比例放入边框；不裁掉状态栏，也不修改截图内容。
def paste_screen(image: Image.Image, source: Path, box: tuple[int, int, int, int],
                 radius: int = 40, frame: int = 10) -> tuple[int, int, int, int]:
    with Image.open(source) as screenshot:
        screen = ImageOps.contain(screenshot.convert("RGB"),
                                  (box[2] - frame * 2, box[3] - frame * 2),
                                  Image.Resampling.LANCZOS)
    x = box[0] + (box[2] - screen.width) // 2
    y = box[1] + (box[3] - screen.height) // 2
    border_box = (x - frame, y - frame, x + screen.width + frame, y + screen.height + frame)
    shadow = Image.new("RGBA", image.size)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((border_box[0] + 6, border_box[1] + 18,
                                   border_box[2] + 6, border_box[3] + 18),
                                  radius=radius + frame, fill=(35, 34, 28, 55))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(border_box, radius=radius + frame, fill="#373733")
    mask = Image.new("L", screen.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen.width, screen.height),
                                           radius=radius, fill=255)
    image.paste(screen, (x, y), mask)
    return x, y, screen.width, screen.height


# 输出去除透明通道的 App Store 标准 PNG。
def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path, format="PNG", compress_level=6)


# 生成单张 iPhone 或 iPad 商店图，每张只使用对应功能的一张真实截图。
def render_store(source: Path, locale: str, metadata: dict, kind: str,
                 page: int, output: Path) -> Path:
    width, height = (1320, 2868) if kind == "iphone" else (2064, 2752)
    scale = width / 1320
    image = Image.new("RGBA", (width, height), PAPER)
    margin = int(92 * scale)
    draw_brand(image, margin, int(101 * scale), scale)
    draw_record(image, (width - int(98 * scale), int(215 * scale)), int(170 * scale))
    layer = headline_layer(metadata["headlines"][page], locale, int(104 * scale),
                           width - margin * 2, INK, output)
    title_y = int(235 * scale)
    image.alpha_composite(layer, (margin, title_y))
    device_top = max(int(590 * scale), title_y + layer.height + int(85 * scale))
    if kind == "iphone":
        paste_screen(image, source,
                     (int(178 * scale), device_top, int(964 * scale),
                      height - device_top - int(140 * scale)),
                     radius=int(47 * scale), frame=int(10 * scale))
    else:
        paste_screen(image, source,
                     (int(102 * scale), device_top, width - int(204 * scale),
                      height - device_top - int(112 * scale)),
                     radius=int(27 * scale), frame=int(8 * scale))
    draw = ImageDraw.Draw(image)
    footer_y = height - int(65 * scale)
    draw.text((margin, footer_y), "iPhone / iPad" if kind == "iphone" else "iPad",
              font=font("en-US", int(20 * scale)), fill=MUTED)
    label = f"{page + 1:02d} / 04"
    chosen = font("en-US", int(20 * scale))
    draw.text((width - margin - chosen.getlength(label), footer_y), label,
              font=chosen, fill=MUTED)
    target = output / "AppStore" / locale / f"{kind}-{page + 1:02d}.png"
    save_png(image, target)
    return target


# 生成多端宣传图，Mac 与手机均来自真实界面截图。
def render_promo(phone: Path, mac: Path, locale: str, metadata: dict,
                 output: Path, social: bool = False) -> Path:
    width, height = (1200, 630) if social else (1920, 1080)
    scale = width / 1920
    image = Image.new("RGBA", (width, height), PAPER)
    margin = int(95 * scale)
    draw_brand(image, margin, int(85 * scale), scale * 1.2)
    draw_record(image, (int(1490 * scale), int(360 * scale)), int(395 * scale))
    title = headline_layer(metadata["headlines"][0], locale, int(108 * scale),
                           int(660 * scale), INK, output)
    image.alpha_composite(title, (margin, int(276 * scale)))
    draw = ImageDraw.Draw(image)
    draw.text((margin, height - int(111 * scale)), "iPhone  /  iPad  /  Mac",
              font=font("en-US", max(18, int(26 * scale))), fill=MUTED)
    draw.text((margin, height - int(65 * scale)), "SynoMusic",
              font=font("en-US", max(13, int(18 * scale))), fill=ACCENT)
    paste_screen(image, mac,
                 (int(772 * scale), int(226 * scale), int(1042 * scale), int(710 * scale)),
                 radius=max(8, int(15 * scale)), frame=max(3, int(6 * scale)))
    phone_height = int((790 if not social else 716) * scale)
    phone_width = int(phone_height * 1320 / 2868)
    paste_screen(image, phone,
                 (width - phone_width - int(71 * scale), height - phone_height - int(41 * scale),
                  phone_width, phone_height),
                 radius=max(12, int(26 * scale)), frame=max(3, int(6 * scale)))
    filename = "social.png" if social else "overview.png"
    target = output / "Promotional" / locale / filename
    save_png(image, target)
    return target


# 为人工复核生成全部已完成区域的首张商店图缩略总览。
def contact_sheet(paths: list[Path], output: Path) -> Path | None:
    if not paths:
        return None
    firsts = [path for path in paths if path.name == "iphone-01.png"]
    if not firsts:
        firsts = paths[:17]
    columns = min(5, len(firsts))
    cell_w, cell_h = 272, 628
    rows = (len(firsts) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_w + 32, rows * cell_h + 30), "#e8e6e0")
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(firsts):
        column, row = index % columns, index // columns
        x, y = 22 + column * cell_w, 20 + row * cell_h
        with Image.open(path) as original:
            thumb = ImageOps.contain(original, (248, 573), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, y + 25))
        draw.text((x, y), path.parent.name, font=font("en-US", 14), fill=INK)
    target = output / "contact-sheet.png"
    save_png(sheet, target)
    return target


# 仅打包本次生成的 PNG，不包含 raw 原图、缓存、源码或临时文件。
def archive_assets(paths: list[Path], sheet: Path | None, output: Path) -> Path:
    target = output / "SynoMusic-1.6.0-Marketing.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED) as archive:
        for path in paths + ([sheet] if sheet else []):
            archive.write(path, path.relative_to(output))
    return target


# 读取命令行参数，生成可用素材；完整打包必须显式传入 archive 参数。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locales", help="Comma-separated App Store locales; default: all")
    parser.add_argument("--raw-root", type=Path, default=ROOT / "build/Marketing/raw")
    parser.add_argument("--output", type=Path, default=ROOT / "build/Marketing")
    parser.add_argument("--allow-partial", action="store_true",
                        help="Render only pages with a real source image")
    parser.add_argument("--archive", action="store_true",
                        help="Create a ZIP after all requested assets are complete")
    args = parser.parse_args()
    metadata = json.loads((SOURCE / "localizations.json").read_text())
    locales = args.locales.split(",") if args.locales else list(metadata)
    unknown = [locale for locale in locales if locale not in metadata]
    if unknown:
        parser.error("Unknown locales: " + ", ".join(unknown))
    args.output.mkdir(parents=True, exist_ok=True)
    jobs = []
    missing = []
    for locale in locales:
        row = metadata[locale]
        for kind in ("iphone", "ipad"):
            for index, page in enumerate(PAGES):
                path = find_raw(args.raw_root, locale, row, f"{kind}-{page}.png")
                jobs.append((locale, kind, index, path))
                if path is None:
                    missing.append(f"{locale}/{kind}-{page}.png")
        if find_raw(args.raw_root, locale, row, "mac-library.png") is None:
            missing.append(f"{locale}/mac-library.png")
    if missing and not args.allow_partial:
        print(json.dumps({"complete": False, "missing": missing}, ensure_ascii=False))
        raise SystemExit("Real screenshots are missing; use --allow-partial only for previews.")
    paths = []
    for locale, kind, index, source in jobs:
        if source:
            paths.append(render_store(source, locale, metadata[locale], kind, index, args.output))
    for locale in locales:
        row = metadata[locale]
        phone = find_raw(args.raw_root, locale, row, "iphone-library.png")
        mac = find_raw(args.raw_root, locale, row, "mac-library.png")
        if phone and mac:
            paths.append(render_promo(phone, mac, locale, row, args.output))
            paths.append(render_promo(phone, mac, locale, row, args.output, social=True))
    sheet = contact_sheet(paths, args.output)
    archive = archive_assets(paths, sheet, args.output) if args.archive and not missing else None
    print(json.dumps({"complete": not missing, "locales": len(locales), "images": len(paths),
                      "missing": missing, "contactSheet": str(sheet) if sheet else None,
                      "archive": str(archive) if archive else None}, ensure_ascii=False))


if __name__ == "__main__":
    main()
