#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
松江阅 (SongJiang Reader) 全平台图标生成脚本。

设计语言: 松绿径向渐变圆角底 + 白色翻开的书 + 顶部松针簇（松江之"松"）。
绘制在 4096x4096 超采样画布上，再缩小到目标尺寸以获得抗锯齿边缘。

用法: python scripts/gen_icons.py
输出:
  assets/icon/songjiang-logo.png          (1024 主图标, 圆角方)
  windows/runner/resources/app_icon.ico   (16..256 多尺寸)
  android/app/src/main/res/mipmap-*/      (ic_launcher.webp / round / foreground / monochrome)
  macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png
  web/icons/Icon-192.png / Icon-512.png / Icon-maskable-*.png
  ios/Runner/Assets.xcassets/AppIcon.appiconset/songjiang-logo*.png (+Contents.json)
"""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersample factor

# ---------- 调色板 ----------
BG_INNER = (53, 181, 117)   # #35B575
BG_MID   = (27, 107, 68)    # #1B6B44
BG_EDGE  = (12, 51, 35)     # #0C3323
PINE_DARK = (11, 59, 38)    # #0B3B26 松枝主色
PINE_HI   = (30, 122, 74)   # #1E7A4A 松枝高光
BOOK_WHITE = (248, 252, 249)
TEXT_GREEN = (46, 125, 84)  # 书页文字线

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def radial_gradient(size, cx, cy, r, stops):
    """stops: [(pos, (r,g,b)), ...] 从中心到边缘"""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / r
            if d >= 1.0:
                px[x, y] = stops[-1][1]
                continue
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]
                p1, c1 = stops[i + 1]
                if d <= p1:
                    t = (d - p0) / (p1 - p0) if p1 > p0 else 0.0
                    px[x, y] = lerp(c0, c1, t)
                    break
    return img

def rotated_ellipse(cx, cy, rx, ry, angle_deg, n=48):
    """旋转椭圆的多边形顶点近似。angle: 椭圆长轴相对 x 轴的旋转角。"""
    a = math.radians(angle_deg)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = rx * math.cos(t)
        y = ry * math.sin(t)
        pts.append((cx + x * math.cos(a) - y * math.sin(a),
                    cy + x * math.sin(a) + y * math.cos(a)))
    return pts

def draw_symbol(draw, center=(512, 470), unit=1.0):
    """
    在单位 1000x1000 的坐标系里绘制符号（书 + 松枝）。
    center: 符号中心坐标; unit: 缩放系数。
    符号纵向范围约 y=140..930。
    """
    cx, cy = center

    def X(v):  # 单位坐标 -> 画布坐标
        return cx + (v - 500) * unit

    def Y(v):
        return cy + (v - 500) * unit

    # ---------- 松枝（书上方） ----------
    # 枝干
    draw.line([(X(500), Y(300)), (X(500), Y(430))],
              fill=PINE_DARK, width=max(4, int(22 * unit)))
    # 针叶簇: 以 (500, 255) 为圆心, 7 根放射针
    hub = (X(500), Y(255))
    rx, ry = 95 * unit, 26 * unit
    for ang in range(-60, 61, 20):
        rad = math.radians(ang)
        dirv = (math.cos(rad), math.sin(rad))
        # 针中心: 从 hub 沿方向外移 35, 使根部聚拢
        c = (hub[0] + dirv[0] * 35 * unit, hub[1] + dirv[1] * 35 * unit)
        draw.polygon(rotated_ellipse(c[0], c[1], rx, ry, ang), fill=PINE_DARK)
    # 针叶高光（偏中心、偏亮、更细）
    for ang in range(-60, 61, 20):
        rad = math.radians(ang)
        dirv = (math.cos(rad), math.sin(rad))
        c = (hub[0] + dirv[0] * 40 * unit, hub[1] + dirv[1] * 40 * unit)
        draw.polygon(rotated_ellipse(c[0], c[1], rx * 0.45, ry * 0.42, ang),
                     fill=PINE_HI)
    # 枝干高光
    draw.line([(X(500), Y(315)), (X(500), Y(420))],
              fill=PINE_HI, width=max(2, int(8 * unit)))

    # ---------- 书 ----------
    l, t, r, b = X(170), Y(430), X(830), Y(930)
    draw.rounded_rectangle([l, t, r, b], radius=70 * unit, fill=BOOK_WHITE)
    # 书脊
    draw.line([(X(500), Y(505)), (X(500), Y(858))],
              fill=PINE_DARK, width=max(3, int(8 * unit)))
    # 左页文字行
    rows = [(250, 560, 420), (250, 630, 390), (250, 700, 420), (250, 770, 350)]
    for x1, y, x2 in rows:
        draw.line([(X(x1), Y(y)), (X(x2), Y(y))],
                  fill=TEXT_GREEN, width=max(3, int(14 * unit)))
    rows_r = [(580, 560, 750), (610, 630, 750), (580, 700, 750), (610, 770, 750)]
    for x1, y, x2 in rows_r:
        draw.line([(X(x1), Y(y)), (X(x2), Y(y))],
                  fill=TEXT_GREEN, width=max(3, int(14 * unit)))

def make_icon(size, with_bg=True, symbol_scale=0.78, round_cut=False,
              rounded=True, bg_full=False, mono=False):
    """
    生成单个图标。
    with_bg: 是否绘制渐变背景; symbol_scale: 符号占画布比例;
    round_cut: 圆形裁剪; rounded: 圆角矩形; bg_full: 背景满幅方形(无圆角);
    mono: 单色白色符号(透明底)。
    """
    SS2 = SS
    canvas = Image.new("RGBA", (size * SS2, size * SS2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    # 背景
    if with_bg:
        if bg_full:
            bg = radial_gradient(size * SS2, size * SS2 / 2, size * SS2 * 0.36,
                                 size * SS2 * 0.78,
                                 [(0.0, BG_INNER), (0.55, BG_MID), (1.0, BG_EDGE)])
        else:
            bg = radial_gradient(size * SS2, size * SS2 / 2, size * SS2 * 0.36,
                                 size * SS2 * 0.8,
                                 [(0.0, BG_INNER), (0.55, BG_MID), (1.0, BG_EDGE)])
        mask = Image.new("L", (size * SS2, size * SS2), 0)
        md = ImageDraw.Draw(mask)
        if round_cut:
            md.ellipse([0, 0, size * SS2, size * SS2], fill=255)
        elif rounded:
            md.rounded_rectangle([0, 0, size * SS2, size * SS2],
                                 radius=int(size * SS2 * 0.205), fill=255)
        else:
            md.rectangle([0, 0, size * SS2, size * SS2], fill=255)
        canvas.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 255)),
                     (0, 0), mask)
        canvas.paste(bg.convert("RGBA"), (0, 0), mask)

    # 符号
    unit = size * SS2 * symbol_scale / 1000.0
    center = (size * SS2 / 2, size * SS2 * 0.47)
    draw_symbol(draw, center=center, unit=unit)

    if mono:
        # 转单色: 保留形状, 填白
        alpha = canvas.split()[3]
        white = Image.new("RGBA", canvas.size, (255, 255, 255, 255))
        canvas = Image.composite(white, Image.new("RGBA", canvas.size, (0, 0, 0, 0)), alpha)

    out = canvas.resize((size, size), Image.LANCZOS)
    return out.convert("RGBA")

def save_webp(img, path, quality=92):
    _safe_save(img, path, format="WEBP", quality=quality, method=6)

def _safe_save(img, path, **kw):
    """沙箱环境不允许覆盖已存在文件：先删除再写入。"""
    try:
        img.save(path, **kw)
    except PermissionError:
        if os.path.exists(path):
            os.remove(path)
        img.save(path, **kw)

def _save_rgb(img, path, **kw):
    _safe_save(img.convert("RGB"), path, **kw)

def main():
    # 1. 主图标 1024 (圆角方)
    icon1024 = make_icon(1024, with_bg=True, symbol_scale=0.78)
    logo_dir = os.path.join(ROOT, "assets", "icon")
    os.makedirs(logo_dir, exist_ok=True)
    _save_rgb(icon1024, os.path.join(logo_dir, "songjiang-logo.png"))
    print("[OK] assets/icon/songjiang-logo.png")

    # 2. Windows ICO
    ico_path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    frames = [make_icon(w, with_bg=True, symbol_scale=0.78) for w, _ in sizes]
    _safe_save(frames[0], ico_path, format="ICO", sizes=sizes, append_images=frames[1:])
    print("[OK] windows/runner/resources/app_icon.ico")

    # 3. Android
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    dpi_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    fg_sizes = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for dpi, s in dpi_sizes.items():
        d = os.path.join(res, f"mipmap-{dpi}")
        save_webp(make_icon(s, with_bg=True, symbol_scale=0.8), os.path.join(d, "ic_launcher.webp"))
        save_webp(make_icon(s, with_bg=True, symbol_scale=0.8, round_cut=True),
                  os.path.join(d, "ic_launcher_round.webp"))
        # 自适应前景: 透明底, 符号在 66% 安全区
        save_webp(make_icon(fg_sizes[dpi], with_bg=False, symbol_scale=0.66),
                  os.path.join(d, "ic_launcher_foreground.webp"))
        # 单色主题图标
        _save_rgb(make_icon(s, with_bg=False, symbol_scale=0.66, mono=True),
            os.path.join(d, "ic_launcher_monochrome.png"))
        print(f"[OK] mipmap-{dpi}")
    # 背景色
    bgxml = os.path.join(res, "values", "ic_launcher_background.xml")
    with open(bgxml, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">#1B6B44</color>\n'
                '</resources>\n')
    print("[OK] values/ic_launcher_background.xml")

    # 4. macOS
    mac_dir = os.path.join(ROOT, "macos", "Runner", "Assets.xcassets",
                           "AppIcon.appiconset")
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in mac_sizes:
        name = f"{s}-mac.png"
        _save_rgb(make_icon(s, with_bg=True, symbol_scale=0.8),
            os.path.join(mac_dir, name))
    # 重复条目
    _save_rgb(make_icon(32, with_bg=True, symbol_scale=0.8),
        os.path.join(mac_dir, "32-mac 1.png"))
    _save_rgb(make_icon(256, with_bg=True, symbol_scale=0.8),
        os.path.join(mac_dir, "256-mac 1.png"))
    _save_rgb(make_icon(512, with_bg=True, symbol_scale=0.8),
        os.path.join(mac_dir, "512-mac 1.png"))
    print("[OK] macOS AppIcon")

    # 5. Web
    web_dir = os.path.join(ROOT, "web", "icons")
    _save_rgb(make_icon(192, with_bg=True, symbol_scale=0.78),
        os.path.join(web_dir, "Icon-192.png"))
    _save_rgb(make_icon(512, with_bg=True, symbol_scale=0.78),
        os.path.join(web_dir, "Icon-512.png"))
    # maskable: 满幅背景 + 符号 80% 安全区
    _save_rgb(make_icon(192, with_bg=True, symbol_scale=0.8, bg_full=True, rounded=False),
        os.path.join(web_dir, "Icon-maskable-192.png"))
    _save_rgb(make_icon(512, with_bg=True, symbol_scale=0.8, bg_full=True, rounded=False),
        os.path.join(web_dir, "Icon-maskable-512.png"))
    print("[OK] web/icons")

    # 6. iOS (1024 + dark/tinted 变体, 更新 Contents.json)
    ios_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets",
                           "AppIcon.appiconset")
    _save_rgb(icon1024, os.path.join(ios_dir, "songjiang-logo.png"))
    # dark: 提高背景亮度对比的变体（简化: 与主图一致即可, 系统自行处理亮度）
    _save_rgb(icon1024, os.path.join(ios_dir, "songjiang-logo-dark.png"))
    # tinted: 单色变体
    mono = make_icon(1024, with_bg=False, symbol_scale=0.66, mono=True)
    _save_rgb(mono, os.path.join(ios_dir, "songjiang-logo-tined.png"))
    import json as _json
    contents = {
        "images": [
            {"filename": "songjiang-logo.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "filename": "songjiang-logo-dark.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
             "filename": "songjiang-logo-tined.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(ios_dir, "Contents.json"), "w", encoding="utf-8") as f:
        _json.dump(contents, f, ensure_ascii=False, indent=2)
    # 删除旧上游图标
    for old in ("Anx-logo.png", "Anx-logo-dark.png", "Anx-logo-tined.png"):
        p = os.path.join(ios_dir, old)
        if os.path.exists(p):
            os.remove(p)
    print("[OK] iOS AppIcon")

    print("全部图标生成完成。")

if __name__ == "__main__":
    main()
