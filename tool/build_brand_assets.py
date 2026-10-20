# -*- coding: utf-8 -*-
"""把新图标铺到项目里所有需要图标的地方（除 launcher icon 之外）。

launcher icon（Android mipmap / iOS AppIcon）由 build_icons.py 生成，
这里补：web PWA、macOS、Windows、iOS 启动图、Android 启动图。
"""
import os

from PIL import Image

MARK = 'tool/icon_source/mark.png'          # 米白透明图形
BG = (11, 59, 51)                            # #0B3B33
CREAM = (243, 239, 227)
PAPER = (247, 244, 236)

mark_cream = Image.open(MARK).convert('RGBA')


def recolored(color):
    m = Image.new('RGBA', mark_cream.size, color + (255,))
    m.putalpha(mark_cream.getchannel('A'))
    return m


mark_ink = recolored(BG)


def compose(mark, px, ratio, bg=None, circle=False):
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    if bg is not None:
        out.paste(Image.new('RGBA', (px, px), bg + (255,)), (0, 0))
    w, h = mark.size
    scale = (px * ratio) / max(w, h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    m = mark.resize((nw, nh), Image.LANCZOS)
    out.alpha_composite(m, ((px - nw) // 2, (px - nh) // 2))
    return out


def ensure(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)


def web():
    """PWA 图标。maskable 版要留安全边（图形缩到 78%）。"""
    for px in (192, 512):
        compose(mark_cream, px, 0.62, bg=BG).convert('RGB').save(
            f'web/icons/Icon-{px}.png')
        compose(mark_cream, px, 0.50, bg=BG).convert('RGB').save(
            f'web/icons/Icon-maskable-{px}.png')
    # favicon 顺手换掉
    compose(mark_cream, 32, 0.62, bg=BG).convert('RGB').save('web/favicon.png')


def macos():
    d = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for name, px in {
        '16-mac.png': 16,
        '32-mac.png': 32,
        '32-mac 1.png': 32,
        '64-mac.png': 64,
        '128-mac.png': 128,
        '256-mac.png': 256,
        '256-mac 1.png': 256,
        '512-mac.png': 512,
        '512-mac 1.png': 512,
        '1024-mac.png': 1024,
    }.items():
        compose(mark_cream, px, 0.62, bg=BG).convert('RGB').save(f'{d}/{name}')


def windows():
    """ICO 内嵌多尺寸，Windows 会按 DPI 挑。"""
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [compose(mark_cream, s, 0.62, bg=BG).convert('RGB') for s in sizes]
    frames[-1].save(
        'windows/runner/resources/app_icon.ico',
        format='ICO',
        sizes=[(s, s) for s in sizes],
        append_images=frames[:-1],
    )


def ios_launch():
    """启动图：白底上放深色图形（米白图形在白底上看不见）。"""
    d = 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    for name, px in {'LaunchImage.png': 168, 'LaunchImage@2x.png': 336,
                     'LaunchImage@3x.png': 504}.items():
        compose(mark_ink, px, 0.92).save(f'{d}/{name}')


def android_launch():
    """启动图：浅色主题用深色图形，深色主题用米白图形。

    尺寸按 96dp 出，覆盖 5 档密度。
    """
    buckets = {'mdpi': 96, 'hdpi': 144, 'xhdpi': 192, 'xxhdpi': 288,
               'xxxhdpi': 384}
    res = 'android/app/src/main/res'
    for dpi, px in buckets.items():
        ensure(f'{res}/drawable-{dpi}/x')
        compose(mark_ink, px, 0.96).save(f'{res}/drawable-{dpi}/launch_mark.png')
        ensure(f'{res}/drawable-night-{dpi}/x')
        compose(mark_cream, px, 0.96).save(
            f'{res}/drawable-night-{dpi}/launch_mark.png')

    light = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/launch_mark" />
    </item>
</layer-list>
'''
    dark = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@mipmap/ic_launcher_background" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/launch_mark" />
    </item>
</layer-list>
'''
    with open(f'{res}/drawable/launch_background.xml', 'w', encoding='utf-8',
              newline='\n') as f:
        f.write(light)
    with open(f'{res}/drawable-v21/launch_background.xml', 'w', encoding='utf-8',
              newline='\n') as f:
        f.write(light)
    ensure(f'{res}/drawable-night/x')
    with open(f'{res}/drawable-night/launch_background.xml', 'w',
              encoding='utf-8', newline='\n') as f:
        f.write(dark)


if __name__ == '__main__':
    web()
    macos()
    windows()
    ios_launch()
    android_launch()
    print('done')
