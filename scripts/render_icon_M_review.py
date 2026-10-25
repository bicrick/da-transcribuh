"""Review renders for the M icon: light + dark Dock at 128 px (0.9.6 vs M) and a
16/32/64 small-size sheet (actual pixels plus nearest-neighbour zoom).
Neighbour Dock tiles are generic placeholders, not real app art.

usage: render_icon_M_review.py <old_iconset_dir> <new_iconset_dir> <out_dir>
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
OLD, NEW, OUT = sys.argv[1:4]
FONT = str(Path(__file__).resolve().parents[1] / 'PromptAnnotator' / 'Fonts' / 'DepartureMono-Regular.otf')


def _sq(n=256, x0=25, x1=231):
    c = np.arange(n) + 0.5; X, Y = np.meshgrid(c, c); cx = (x0 + x1) / 2; r = (x1 - x0) / 2
    return ((np.abs((X - cx) / r) ** 5 + np.abs((Y - cx) / r) ** 5) <= 1).astype(float)


def _ph(face, fn):
    im = Image.new('RGBA', (256, 256), face + (255,)); fn(ImageDraw.Draw(im))
    a = np.asarray(im).copy(); a[..., 3] = (_sq() * 255).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


def _lines(d):
    for y in range(65, 200, 14): d.line((45, y, 211, y), fill=(170, 190, 230), width=2)
    d.line((75, 35, 75, 225), fill=(230, 120, 120), width=2)


neighbours = [
    _ph((200, 205, 212), lambda d: (d.rectangle((75, 65, 181, 190), fill=(250, 250, 250), outline=(120, 120, 120), width=3),
                                    d.ellipse((95, 85, 160, 150), outline=(70, 110, 170), width=8))),
    _ph((28, 28, 30), lambda d: (d.ellipse((72, 72, 184, 184), outline=(80, 160, 240), width=18),
                                 d.line((150, 150, 190, 190), fill=(80, 160, 240), width=18))),
    _ph((250, 250, 248), _lines),
]
F = lambda n: ImageFont.truetype(FONT, n)
L = lambda d, s: Image.open(f'{d}/icon_{s}.png').convert('RGBA')

def dock(theme):
    ic, gap = 128, 28
    icons = [n.resize((ic, ic), Image.LANCZOS) for n in neighbours] + [L(OLD, 128), L(NEW, 128)]
    labels = [''] * len(neighbours) + ['0.9.6', 'new M']
    n = len(icons) + 1; bw = n * (ic + gap) + gap + 40
    W, H = bw + 120, 330
    top = (246, 246, 246) if theme == 'light' else (30, 30, 32)
    img = Image.new('RGB', (W, H), top); dr = ImageDraw.Draw(img)
    bar = (168, 168, 168) if theme == 'light' else (62, 62, 66)
    x0 = y0 = 60
    dr.rounded_rectangle((x0, y0, x0 + bw, y0 + ic + 2 * gap + 10), radius=36, fill=bar,
                         outline=(150, 150, 150) if theme == 'light' else (85, 85, 90), width=2)
    x = x0 + gap
    for i, im in enumerate(icons):
        img.paste(im, (x, y0 + gap), im)
        dr.ellipse((x + ic // 2 - 5, y0 + gap + ic + 8, x + ic // 2 + 5, y0 + gap + ic + 18),
                   fill=(250, 250, 250) if theme == 'light' else (200, 200, 200))
        if labels[i]:
            f = F(34); w = dr.textlength(labels[i], font=f)
            dr.text((x + ic // 2 - w / 2, y0 + ic + 2 * gap + 30), labels[i], font=f,
                    fill=(30, 30, 30) if theme == 'light' else (230, 230, 230))
        x += ic + gap
    dr.line((x + 2, y0 + gap + 10, x + 2, y0 + gap + ic - 10), fill=(235, 235, 235), width=3); x += gap
    dr.rounded_rectangle((x + 20, y0 + gap + 10, x + ic - 20, y0 + gap + ic), radius=10, fill=(120, 120, 124))
    p = f'{OUT}/dock-{theme}.png'; img.save(p); print(p, img.size)

def small():
    Z = 8; pad = 40; colw = 64 * Z + pad
    W = pad + 3 * (64 + pad) + pad + 2 * (64 * Z // 2 + pad); rowh = 64 * Z // 2 + 150
    img = Image.new('RGB', (W, 2 * (2 * rowh) + 40), (246, 246, 246)); dr = ImageDraw.Draw(img)
    y = 20
    for bg, fg in (((246, 246, 246), (30, 30, 30)), ((30, 30, 32), (230, 230, 230))):
        dr.rectangle((0, y - 20, W, y + 2 * rowh - 20), fill=bg)
        for name, d in (('0.9.6', OLD), ('new M', NEW)):
            dr.text((pad, y), name, font=F(36), fill=fg)
            x = pad
            for s in (16, 32, 64):
                im = L(d, s); img.paste(im, (x, y + 70 + (64 - s) // 2), im)
                dr.text((x, y + 150), f'{s}', font=F(24), fill=fg); x += 64 + pad
            x += pad
            for s in (16, 32):
                z = L(d, s).resize((64 * Z // 2 if s == 32 else 64 * Z // 2,) * 2, Image.NEAREST)
                img.paste(z, (x, y + 70), z)
                dr.text((x, y + 80 + z.height), f'{s} px zoomed', font=F(24), fill=fg); x += z.width + pad
            y += rowh
    p = f'{OUT}/small-sizes.png'; img.save(p); print(p, img.size)

dock('light'); dock('dark'); small()
