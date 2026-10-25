"""Fit the existing dt card AppIcon onto the macOS squircle grid.

Keeps every pixel of the art inside the card (mark, face, hairline, bevel) and only
changes the silhouette: the square card with its offset bevel becomes one opaque
squircle body, outlined in the same black hairline. macOS 26 shows icons that are
not squircle-shaped inside a grey "legacy" platter; a full squircle body avoids it.
"""
import sys
import numpy as np
from PIL import Image

N_EXP = 5.0           # superellipse exponent, close to the macOS app icon shape
G0, G1 = 99, 925      # card + bevel bounding box on the 1024 grid (unchanged)
BEVEL = 29            # hard offset bevel on the 1024 grid (unchanged)

def mask(size, x0, x1, ss=8):
    n = size * ss
    c = (np.arange(n) + 0.5) / ss
    cx = (x0 + x1) / 2; r = (x1 - x0) / 2
    X, Y = np.meshgrid(c, c)
    inside = (np.abs((X - cx) / r) ** N_EXP + np.abs((Y - cx) / r) ** N_EXP) <= 1.0
    return inside.reshape(size, ss, size, ss).mean(axis=(1, 3))

def fit(src, size):
    im = np.asarray(Image.open(src).convert('RGBA')).astype(np.float64) / 255.0
    s = size / 1024.0
    x0, x1 = G0 * s, G1 * s
    hw = max(1.0, size / 128.0)
    bev = BEVEL * s
    body = mask(size, x0, x1)
    # face = the body shifted up-left by the bevel, clipped to the body; the black
    # crescent left at the lower right is the same hard offset bevel as before.
    inner = mask(size, x0 + hw, x1 - hw) * mask(size, x0 - bev + hw, x1 - bev - hw)
    rgb = im[..., :3].copy(); a = im[..., 3:4]
    # transparent notches left by the offset bevel become bevel black
    rgb = rgb * a
    out = np.zeros((size, size, 4))
    # inside the hairline: the original art; on the hairline ring: black
    out[..., :3] = rgb * inner[..., None]
    out[..., 3] = body
    o = (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(o, 'RGBA')

if __name__ == '__main__':
    src_dir, dst_dir = sys.argv[1], sys.argv[2]
    for size in (16, 32, 64, 128, 256, 512, 1024):
        fit(f'{src_dir}/icon_{size}.png', size).save(f'{dst_dir}/icon_{size}.png')
        print('wrote', size)
