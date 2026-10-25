"""Review renders for the dark AppIcon: Dock mockups (light + dark wallpaper) and small sizes.

usage: render_icon_dark_review.py <work_dir_with_light_a_c> <out_dir>
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'PromptAnnotator' / 'Fonts' / 'DepartureMono-Regular.otf'
W, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
NAMES = [('light', 'light (0.9.5)'), ('a', 'A v1 pale bevel'), ('c', 'A v2 dark bevel')]


def font(px):
    return ImageFont.truetype(str(FONT), px)


def grad(w, h, top, bot):
    im = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return im


def icon(v, px):
    im = Image.open(W / v / 'icon_1024.png').convert('RGBA')
    return im.resize((px, px), Image.LANCZOS)


def dock(mode):
    w, h = 1600, 760
    if mode == 'light':
        bg = grad(w, h, (214, 226, 240), (246, 238, 226)); dock_fill = (255, 255, 255, 110); edge = (255, 255, 255, 170); txt = (30, 30, 30)
    else:
        bg = grad(w, h, (26, 30, 46), (52, 44, 66)); dock_fill = (40, 40, 44, 150); edge = (255, 255, 255, 40); txt = (235, 235, 235)
    bg = bg.convert('RGBA')
    d = ImageDraw.Draw(bg)
    d.text((60, 50), f'Dock mockup on {mode} wallpaper  (64pt @2x = 128px)', font=font(30), fill=txt)
    icon_px, gap, pad = 256, 70, 34
    n = len(NAMES)
    dw = n * icon_px + (n - 1) * gap + pad * 2
    dx, dy, dh = (w - dw) // 2, h - 330, icon_px + pad * 2
    layer = Image.new('RGBA', bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle([dx, dy, dx + dw, dy + dh], radius=60, fill=dock_fill, outline=edge, width=2)
    blur = bg.crop((dx, dy, dx + dw, dy + dh)).filter(ImageFilter.GaussianBlur(30))
    bg.paste(blur, (dx, dy))
    bg = Image.alpha_composite(bg, layer)
    for i, (v, label) in enumerate(NAMES):
        x = dx + pad + i * (icon_px + gap); y = dy + pad
        ic = icon(v, icon_px)
        sh = Image.new('RGBA', bg.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 90), (x, y + 10), ic.split()[3])
        bg = Image.alpha_composite(bg, sh.filter(ImageFilter.GaussianBlur(10)))
        bg.alpha_composite(ic, (x, y))
        dd = ImageDraw.Draw(bg)
        tw = dd.textlength(label, font=font(26))
        dd.text((x + icon_px / 2 - tw / 2, dy - 60), label, font=font(26), fill=txt)
    bg.convert('RGB').save(OUT / f'dock-{mode}.png')


def small():
    w, h = 1600, 900
    im = Image.new('RGB', (w, h), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([w // 2, 70, w, h], fill=(30, 30, 32))
    d.text((40, 24), '16 / 32 / 64 px at 1:1, then 16 at 8x and 32 at 6x (nearest)   light bg | dark bg', font=font(24), fill=(0, 0, 0))
    for half, bgc, txt in ((0, (255, 255, 255), (0, 0, 0)), (1, (30, 30, 32), (235, 235, 235))):
        ox = half * (w // 2) + 40
        for r, (v, label) in enumerate(NAMES):
            y = 90 + r * 270
            d.text((ox, y), label, font=font(22), fill=txt)
            x = ox
            for s in (16, 32, 64):
                ic = Image.open(W / v / f'icon_{s}.png').convert('RGBA')
                im.paste(ic, (x, y + 40 + (64 - s)), ic); x += s + 24
            x += 20
            for s in (16, 32):
                ic = Image.open(W / v / f'icon_{s}.png').convert('RGBA').resize((s * 8 if s == 16 else s * 6,) * 2, Image.NEAREST)
                im.paste(ic, (x, y + 36), ic); x += ic.size[0] + 24
    im.save(OUT / 'small-sizes.png')


def side_by_side():
    im = Image.new('RGB', (3 * 560 + 40, 640), (128, 128, 128))
    d = ImageDraw.Draw(im)
    for i, (v, label) in enumerate(NAMES):
        im.paste(icon(v, 512), (20 + i * 560 + 14, 20), icon(v, 512))
        d.text((20 + i * 560 + 30, 560), label, font=font(28), fill=(255, 255, 255))
    im.save(OUT / 'side-by-side-1024.png')


dock('light'); dock('dark'); small(); side_by_side()
print('ok', sorted(p.name for p in OUT.iterdir()))
