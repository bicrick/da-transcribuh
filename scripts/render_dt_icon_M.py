"""Render the "M" AppIcon: big Departure Mono dt on a graphite squircle where the
stems double as waveform bars (d stem pale and a bit taller, t stem red and tallest).

Frame follows the 0.9.6 icon (render_dt_icon_dark.py / fit_icon_squircle.py):
superellipse n=5 on the 99..925 grid, 8 px ink hairline, pale #F2F2F2 offset bevel
of 29 px down-right, graphite face.

64..1024 are box-downsampled from a 4x supersampled 1024 render.
16 and 32 are re-drawn on the pixel grid: the frame comes from the downsampled
art-free tile and the mark is placed as hard pixels (1 px red stem at 16, 2 px at 32),
and the downsampled frame colours are snapped to the icon palette.

usage: render_dt_icon_M.py <dst_dir>
"""
import sys
import numpy as np
from PIL import Image

S = 1024; G0, G1, N_EXP, BEV, HAIR, HI = 99, 925, 5.0, 29, 8, 14
GRAPH = (43, 43, 43); GRAPH_HI = (70, 70, 70); PALE = (242, 242, 242)
INK = (14, 14, 16); SHADOW = (20, 20, 22); RED = (224, 58, 47)
SIZES = (16, 32, 64, 128, 256, 512, 1024)

# Departure Mono 11px bitmaps (5x8)
D = ['....#', '....#', '.##.#', '#..##', '#...#', '#...#', '#..##', '.##.#']
T = ['.#...', '.#...', '#####', '.#...', '.#...', '.#...', '.#..#', '..##.']

def sq(x0, x1, dx=0.0, dy=0.0, ss=4):
    n = S * ss; c = (np.arange(n) + 0.5) / ss
    cx = (x0 + x1) / 2 + dx; cy = (x0 + x1) / 2 + dy; r = (x1 - x0) / 2
    X, Y = np.meshgrid(c, c)
    m = (np.abs((X - cx) / r) ** N_EXP + np.abs((Y - cy) / r) ** N_EXP) <= 1.0
    return m.reshape(S, ss, S, ss).mean(axis=(1, 3))


class Canvas:
    def __init__(self):
        self.rgb = np.zeros((S, S, 3)); self.a = np.zeros((S, S))
    def paint(self, m, col):
        self.rgb = self.rgb * (1 - m[..., None]) + np.array(col, float) * m[..., None]
    def rect(self, x, y, w, h, col):
        m = np.zeros((S, S)); m[int(y):int(y + h), int(x):int(x + w)] = 1; self.paint(m, col)
    def img(self):
        return Image.fromarray((np.dstack([np.clip(self.rgb, 0, 255), self.a * 255]) + 0.5).astype(np.uint8), 'RGBA')


def tile():
    h = HAIR
    body = sq(G0, G1)
    ring_in = sq(G0 + h, G1 - h)
    face_o = sq(G0 + h, G1 - h) * sq(G0 + h, G1 - h, -BEV, -BEV)
    face = sq(G0 + 2 * h, G1 - 2 * h) * sq(G0 + 2 * h, G1 - 2 * h, -BEV, -BEV)
    face_sh = sq(G0 + 2 * h, G1 - 2 * h, HI, HI) * sq(G0 + 2 * h, G1 - 2 * h, HI - BEV, HI - BEV)
    c = Canvas(); c.a = body
    c.paint(np.ones((S, S)), INK); c.paint(ring_in, PALE); c.paint(face_o, INK)
    c.paint(face, GRAPH); c.paint(np.clip(face - face_sh, 0, 1), GRAPH_HI)
    c.face = face
    return c


def mark_1024(c):
    pre = c.rgb.copy(); u = 56; fc = 498; sh = 28
    x, y = fc - 308, fc - 224; tx = x + 6 * u
    dm = [r[:4] + '.' for r in D]; tm = [r[0] + '.' + r[2:] for r in T]
    px = [(x + i * u, y + j * u) for j, r in enumerate(dm) for i, ch in enumerate(r) if ch == '#']
    px += [(tx + i * u, y + j * u) for j, r in enumerate(tm) for i, ch in enumerate(r) if ch == '#']
    dstem = (x + 4 * u, y - u, u, 9 * u); tstem = (tx + u, y - 2 * u, u, 11 * u)
    for a, b in px: c.rect(a + sh, b + sh, u, u, SHADOW)
    for b in (dstem, tstem): c.rect(b[0] + sh, b[1] + sh, b[2], b[3], SHADOW)
    for a, b in px: c.rect(a, b, u, u, PALE)
    c.rect(*dstem, PALE); c.rect(*tstem, RED)
    m = c.face[..., None]; c.rgb = pre * (1 - m) + c.rgb * m


# 32 px mark, 17 x 19, 2 px strokes. Departure Mono proportions scaled 1.75x and
# snapped: red t stem rows 0-18, d stem rows 2-16, crossbar and bowl top rows 7-8.
MARK32 = [
    '...........rr....',
    '...........rr....',
    '......##...rr....',
    '......##...rr....',
    '......##...rr....',
    '......##...rr....',
    '......##...rr....',
    '..######.##rr####',
    '.#######.##rr####',
    '##....##...rr....',
    '##....##...rr....',
    '##....##...rr....',
    '##....##...rr....',
    '##....##...rr....',
    '##....##...rr..##',
    '.#######...rr..##',
    '..######...rr##..',
    '...........rr....',
    '...........rr....',
]
# 16 px mark, 9 x 9, 1 px strokes, 1 px red stem.
MARK16 = [
    '......r..',
    '...#..r..',
    '...#..r..',
    '.###.#r##',
    '#..#..r..',
    '#..#..r..',
    '#..#..r.#',
    '.###..r#.',
    '......r..',
]


def hint_small(img, size, rows, shadow):
    rgb = np.asarray(img.convert('RGBA')).astype(float)
    # snap the downsampled frame to the palette so the rim and bevel stay crisp
    pal = np.array([INK, PALE, GRAPH], float)
    d = ((rgb[..., None, :3] - pal[None, None]) ** 2).sum(-1)
    rgb[..., :3] = pal[d.argmin(-1)]
    # drop isolated pale pixels where the bevel ring peeks out at the corners
    pale = (rgb[..., :3] == PALE).all(-1)
    nb = np.zeros_like(pale)
    nb[1:] |= pale[:-1]; nb[:-1] |= pale[1:]; nb[:, 1:] |= pale[:, :-1]; nb[:, :-1] |= pale[:, 1:]
    rgb[pale & ~nb, :3] = GRAPH
    # full-face pixels (no rim, no bevel) give the centring box
    face = np.asarray(Image.fromarray((tile_face_mask() * 255).astype(np.uint8)).resize((size, size), Image.BOX)) >= 254
    ys, xs = np.where(face)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = len(rows), len(rows[0])
    left = x0 + (x1 - x0 + 1 - w - (1 if shadow else 0)) // 2
    top = y0 + (y1 - y0 + 1 - h - (1 if shadow else 0)) // 2
    pts = [(top + j, left + i, ch) for j, r in enumerate(rows) for i, ch in enumerate(r) if ch in '#r']
    if shadow:
        for yy, xx, _ in pts:
            if face[yy + 1, xx + 1]: rgb[yy + 1, xx + 1, :3] = SHADOW
    for yy, xx, ch in pts:
        assert face[yy, xx], (size, yy, xx)
        rgb[yy, xx, :3] = PALE if ch == '#' else RED
    return Image.fromarray((rgb + 0.5).astype(np.uint8), 'RGBA')


_fm = None
def tile_face_mask():
    global _fm
    if _fm is None:
        h = HAIR
        _fm = sq(G0 + 2 * h, G1 - 2 * h) * sq(G0 + 2 * h, G1 - 2 * h, -BEV, -BEV)
    return _fm


def render_all(dst):
    c = tile(); plain = c.img()
    mark_1024(c); full = c.img()
    out = {}
    for s in SIZES:
        if s == 1024: im = full
        elif s in (16, 32):
            base = plain.resize((s, s), Image.BOX)
            im = hint_small(base, s, MARK16 if s == 16 else MARK32, shadow=(s == 32))
        else: im = full.resize((s, s), Image.BOX)
        im.save(f'{dst}/icon_{s}.png'); out[s] = im
        print('wrote', s)
    return out


if __name__ == '__main__':
    render_all(sys.argv[1])
