"""Render the graphite (dark) AppIcon from the light squircle AppIcon (PR #49).

The light icon is pure grayscale: white face, black ink (d, inverted-t block,
hairline, offset bevel). Recolouring by luminance keeps every hinted pixel of the
small sizes and the exact squircle silhouette, so macOS 26 still treats it as a
native (non-legacy) icon. Colours come from the app's dark Ink theme (InkTheme.swift):
  markFace #3A3A3D (graphite face), markInk / markInvertFace / bevel #F2F2F2.

Variants
  a  "inverted"  full theme inversion, like InkDtMark in dark mode: graphite face,
                 light d, light t block, light hairline and light bevel.
  b  "graphite"  graphite face with the light mark, but the outer hairline and the
                 offset bevel stay black, like the light icon's edge.

16 and 32 px are re-drawn on the pixel grid instead of recoloured: the downsampled
mark is a grey smudge at those sizes, so the d + inverted t are placed as hard pixels
(a 3x5 hand-drawn pair at 16, Departure Mono's native 5x8 bitmaps at 32) for full
contrast. The silhouette, rim and bevel pixels still come from the light source.

usage: render_dt_icon_dark.py <a|b> <src_iconset> <dst_dir>
"""
import sys
import numpy as np
from PIL import Image

FACE = np.array([0x3A, 0x3A, 0x3D], float)   # Ink.markFace (dark)
INK = np.array([0xF2, 0xF2, 0xF2], float)    # Ink.markInk / bevel (dark)
EDGE_B = np.array([0x00, 0x00, 0x00], float)  # variant b keeps the black edge

N_EXP, G0, G1, BEVEL = 5.0, 99, 925, 29      # same grid as fit_icon_squircle.py
SIZES = (16, 32, 64, 128, 256, 512, 1024)


def mask(size, x0, x1, ss=8):
    n = size * ss
    c = (np.arange(n) + 0.5) / ss
    cx = (x0 + x1) / 2; r = (x1 - x0) / 2
    X, Y = np.meshgrid(c, c)
    inside = (np.abs((X - cx) / r) ** N_EXP + np.abs((Y - cx) / r) ** N_EXP) <= 1.0
    return inside.reshape(size, ss, size, ss).mean(axis=(1, 3))


def inner_face(size):
    s = size / 1024.0
    x0, x1 = G0 * s, G1 * s
    hw = max(1.0, size / 128.0); bev = BEVEL * s
    return mask(size, x0 + hw, x1 - hw) * mask(size, x0 - bev + hw, x1 - bev - hw)


D16 = ["..#", "..#", "###", "#.#", "###"]
T16 = [".#.", "###", ".#.", ".#.", ".##"]


def font_bitmap(ch, px=11):
    from PIL import ImageDraw, ImageFont
    from pathlib import Path
    f = ImageFont.truetype(str(Path(__file__).resolve().parents[1] / 'PromptAnnotator' / 'Fonts' / 'DepartureMono-Regular.otf'), px)
    im = Image.new('L', (px * 2, px * 2), 0)
    d = ImageDraw.Draw(im); d.fontmode = '1'; d.text((2, 2), ch, font=f, fill=255)
    c = np.asarray(im.crop(im.getbbox())) > 0
    return c


def hint_small(rgb, size):
    """Repaint the inside of the face and place a pixel-exact mark (16 / 32 px)."""
    k = inner_face(size)
    full = k >= 0.999
    ys, xs = np.where(full)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    rgb[full] = FACE
    if size == 16:
        dm = np.array([[c == '#' for c in r] for r in D16]); tm = np.array([[c == '#' for c in r] for r in T16])
        padx, pady, gap = 1, 1, 1
    else:
        dm, tm = font_bitmap('d'), font_bitmap('t')
        padx, pady, gap = 2, 1, 1
    bw, bh = tm.shape[1] + 2 * padx, tm.shape[0] + 2 * pady
    tw, th = dm.shape[1] + gap + bw, max(dm.shape[0], bh)
    left = x0 + (x1 - x0 + 1 - tw) // 2
    top = y0 + (y1 - y0 + 1 - th) // 2
    by = top + (th - bh) // 2
    # d sits on the same baseline as the t glyph inside the block
    dy = by + pady + tm.shape[0] - dm.shape[0]
    for (yy, xx) in zip(*np.where(dm)):
        rgb[dy + yy, left + xx] = INK
    bx = left + dm.shape[1] + gap
    rgb[by:by + bh, bx:bx + bw] = INK
    for (yy, xx) in zip(*np.where(tm)):
        rgb[by + pady + yy, bx + padx + xx] = FACE
    return rgb


def render(variant, src, size):
    im = np.asarray(Image.open(src).convert('RGBA')).astype(float)
    lum = im[..., 0] / 255.0                      # grayscale source: 1 = face, 0 = ink
    a = im[..., 3]
    inv = INK[None, None] * (1 - lum[..., None]) + FACE[None, None] * lum[..., None]
    if variant == 'a':
        rgb = inv
    else:
        k = inner_face(size)[..., None]           # 1 inside the hairline, 0 on the rim/bevel
        rgb = inv * k + EDGE_B[None, None] * (1 - k)
    if size in (16, 32):
        rgb = hint_small(np.array(rgb), size)
    out = np.dstack([np.clip(rgb, 0, 255), a])
    return Image.fromarray((out + 0.5).astype(np.uint8), 'RGBA')


if __name__ == '__main__':
    variant, src_dir, dst_dir = sys.argv[1:4]
    assert variant in ('a', 'b')
    for size in SIZES:
        render(variant, f'{src_dir}/icon_{size}.png', size).save(f'{dst_dir}/icon_{size}.png')
        print('wrote', variant, size)
