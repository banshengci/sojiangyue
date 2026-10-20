# -*- coding: utf-8 -*-
"""从候选图 A 生成全套应用图标（Android 自适应 + 传统 + iOS）。

思路：候选图是「深绿底 + 米白图形」的两色图，先用亮度差抠出 alpha，
把图形统一成米白（顺便去掉纸纹，小尺寸下更干净），再按各平台尺寸合成。
"""
import io
import os

from PIL import Image, ImageDraw, ImageFilter

SRC = 'tool/icon_source/source-pine-book.png'

BG = (11, 59, 51)          # #0B3B33 深松绿
BG_DARK = (6, 35, 29)      # #06231D 更深（iOS 深色模式）
INK = (243, 239, 227)      # #F3EFE3 米白


def extract_mark(path):
    """把图形从底色里抠出来，返回 RGBA、图形贴着画布边。"""
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()

    alpha = Image.new('L', (w, h), 0)
    ap = alpha.load()
    # 底深绿 luma≈44，图形米白 luma≈239。
    # lo 必须高过底色的纸纹（纸纹会把 luma 抬到 90 上下），否则整张图会留下
    # 一圈淡淡的矩形残影——自适应图标是透明前景，这圈残影会直接显示出来。
    lo, hi = 130.0, 205.0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            luma = 0.299 * r + 0.587 * g + 0.114 * b
            v = (luma - lo) / (hi - lo)
            if v <= 0:
                ap[x, y] = 0
            elif v >= 1:
                ap[x, y] = 255
            else:
                ap[x, y] = int(v * 255)

    # 边缘抗锯齿：轻微模糊后重新归一化，低于 60 的一律抹掉
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    alpha = alpha.point(lambda v: 0 if v < 60 else min(255, int((v - 60) * 255 / 195)))

    solid = Image.new('RGBA', (w, h), INK + (255,))
    solid.putalpha(alpha)
    bbox = solid.getbbox()
    return solid.crop(bbox)


def place(mark, canvas_px, ratio, bg=None, circle=False, color=None):
    """把图形按比例居中放进画布；bg 为空则透明。"""
    out = Image.new('RGBA', (canvas_px, canvas_px), (0, 0, 0, 0))
    if bg is not None:
        if circle:
            d = ImageDraw.Draw(out)
            d.ellipse([0, 0, canvas_px - 1, canvas_px - 1], fill=bg + (255,))
        else:
            out.paste(Image.new('RGBA', out.size, bg + (255,)), (0, 0))

    mw, mh = mark.size
    target = canvas_px * ratio
    scale = target / max(mw, mh)
    nw, nh = max(1, round(mw * scale)), max(1, round(mh * scale))
    resized = mark.resize((nw, nh), Image.LANCZOS)
    if color is None:
        m = resized
    else:
        m = Image.new('RGBA', (nw, nh), color + (255,))
        m.putalpha(resized.getchannel('A'))
    out.alpha_composite(m, ((canvas_px - nw) // 2, (canvas_px - nh) // 2))
    return out


def save_webp(im, path):
    im.save(path, 'WEBP', lossless=True, quality=100, method=6)


def save_png(im, path):
    im.save(path, 'PNG', optimize=True)


def main():
    mark = extract_mark(SRC)
    print('mark bbox size:', mark.size)
    save_png(mark, 'tool/icon_source/mark.png')

    res = 'android/app/src/main/res'
    legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

    for dpi, px in legacy.items():
        # 传统方图：满版底色
        square = place(mark, px, 0.64, bg=BG)
        save_webp(square, f'{res}/mipmap-{dpi}/ic_launcher.webp')
        # 圆形：底色裁成圆，四角透明
        rnd = place(mark, px, 0.58, bg=BG, circle=True)
        save_webp(rnd, f'{res}/mipmap-{dpi}/ic_launcher_round.webp')

    for dpi, px in adaptive.items():
        # 自适应前景：透明底，图形缩到安全区内
        fg = place(mark, px, 0.56)
        save_webp(fg, f'{res}/mipmap-{dpi}/ic_launcher_foreground.webp')
        # 自适应背景：纯色
        save_png(Image.new('RGBA', (px, px), BG + (255,)),
                 f'{res}/mipmap-{dpi}/ic_launcher_background.png')
        # 单色（Android 13 主题图标，只看 alpha）
        mono = place(mark, px, 0.56, color=(255, 255, 255))
        save_png(mono, f'{res}/mipmap-{dpi}/ic_launcher_monochrome.png')

    # iOS：1024 满版，系统自己切圆角
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    save_png(place(mark, 1024, 0.62, bg=BG).convert('RGB'), f'{ios}/songjiang-logo.png')
    save_png(place(mark, 1024, 0.62, bg=BG_DARK).convert('RGB'),
             f'{ios}/songjiang-logo-dark.png')
    gray = place(mark, 1024, 0.62, bg=(214, 210, 199), color=(58, 56, 50)).convert('RGB')
    save_png(gray, f'{ios}/songjiang-logo-tined.png')

    print('done')


if __name__ == '__main__':
    main()
