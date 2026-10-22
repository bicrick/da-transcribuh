#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
from typing import NamedTuple

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT_BRAND = ROOT / "assets" / "brand"
OUT_MOCKS = OUT_BRAND / "mocks"
README = ROOT / "README.md"

S = 2.0
WORDMARK = "da transcribuh"
PITCH = "free, fast, on-device voice to text in ur menu bar."
BANNER_TAG = "talk. it types. drag if u want the picture too."
DEMO_CAPTION = "talk. it types. grab the picture."
WAVE_HEIGHTS = (
    0.25, 0.55, 0.9, 0.45, 0.7, 1.0, 0.6, 0.85, 0.35, 0.75, 0.5, 0.95, 0.4, 0.65, 0.3,
)

RGB = tuple[int, int, int]


def rgb(hex_color: str) -> RGB:
    h = hex_color.removeprefix("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


class _Palette(NamedTuple):
    window: RGB
    front: RGB
    fill: RGB
    label: RGB
    secondary: RGB
    hairline: RGB
    record: RGB
    bevel: RGB
    mark_face: RGB
    mark_ink: RGB
    mark_inv_face: RGB
    mark_inv_ink: RGB


Ink = _Palette(
    window=rgb("#2C2C2E"),
    front=rgb("#3A3A3D"),
    fill=rgb("#353538"),
    label=rgb("#F2F2F2"),
    secondary=rgb("#A8A8AD"),
    hairline=rgb("#4A4A4E"),
    record=rgb("#ED1C24"),
    bevel=rgb("#F2F2F2"),
    mark_face=rgb("#3A3A3D"),
    mark_ink=rgb("#F2F2F2"),
    mark_inv_face=rgb("#F2F2F2"),
    mark_inv_ink=rgb("#3A3A3D"),
)


def stroke_px(s: float) -> int:
    return max(1, int(round(2 * s)))


def bevel_px(s: float) -> int:
    return max(1, int(round(3 * s)))


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def text_size(d: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = d.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def pane(
    d: ImageDraw.ImageDraw,
    x: float,
    y: float,
    w: float,
    h: float,
    fill: RGB,
    s: float,
) -> None:
    b = bevel_px(s)
    d.rectangle([x + b, y + b, x + w + b, y + h + b], fill=Ink.bevel)
    d.rectangle([x, y, x + w, y + h], fill=fill, outline=Ink.label, width=stroke_px(s))


def draw_mark(d: ImageDraw.ImageDraw, x: float, y: float, side: float, s: float) -> None:
    pane(d, x, y, side, side, Ink.mark_face, s)
    f = font(side * 0.42)
    db = d.textbbox((0, 0), "d", font=f)
    dw, dh = db[2] - db[0], db[3] - db[1]
    tb = d.textbbox((0, 0), "t", font=f)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    pad_x, pad_y, gap = 5 * s, 4 * s, 4 * s
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = x + (side - total) / 2
    top = y + (side - max(dh, bh)) / 2
    d.text((left - db[0], top + (max(dh, bh) - dh) / 2 - db[1]), "d", font=f, fill=Ink.mark_ink)
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    d.rectangle([bx, by, bx + bw, by + bh], fill=Ink.mark_inv_face)
    d.text(
        (bx + (bw - tw) / 2 - tb[0], by + (bh - th) / 2 - tb[1]),
        "t",
        font=f,
        fill=Ink.mark_inv_ink,
    )


def draw_waveform(
    d: ImageDraw.ImageDraw,
    x: float,
    y: float,
    w: float,
    h: float,
    s: float,
) -> tuple[int, int]:
    bar_w = max(2 * s, w / (len(WAVE_HEIGHTS) * 1.6))
    gap = bar_w * 0.55
    cx = x
    mid = y + h / 2
    sample = (int(x + w / 2), int(mid))
    for i, frac in enumerate(WAVE_HEIGHTS):
        bh = max(2 * s, h * frac)
        d.rectangle([cx, mid - bh / 2, cx + bar_w, mid + bh / 2], fill=Ink.label)
        if frac == 1.0:
            sample = (int(cx + bar_w / 2), int(mid))
        cx += bar_w + gap
        if cx > x + w:
            break
    return sample


class Island(NamedTuple):
    w: float
    h: float
    record: tuple[int, int]
    wave: tuple[int, int]


class IslandMetrics(NamedTuple):
    w: float
    h: float
    pad: float
    rec: float
    tw: float
    th: float
    gap: float
    wave_w: float
    wave_h: float
    chip_w: float
    inner_h: float


def island_metrics(
    d: ImageDraw.ImageDraw,
    s: float,
    timer: str,
    chip: int | None,
) -> IslandMetrics:
    pad = 10 * s
    rec = 10 * s
    tw, th = text_size(d, timer, font(12 * s))
    wave_w, wave_h = 88 * s, 22 * s
    chip_w = (36 * s) if chip is not None else 0
    gap = 10 * s
    inner_h = max(rec, th, wave_h, 18 * s)
    h = pad * 2 + inner_h
    w = pad + rec + 8 * s + tw + gap + wave_w
    if chip is not None:
        w += gap + chip_w
    w += pad
    return IslandMetrics(w, h, pad, rec, tw, th, gap, wave_w, wave_h, chip_w, inner_h)


def draw_island(
    d: ImageDraw.ImageDraw,
    x: float,
    y: float,
    s: float,
    *,
    timer: str = "0:12",
    chip: int | None = 1,
) -> Island:
    m = island_metrics(d, s, timer, chip)
    timer_f = font(12 * s)

    pane(d, x, y, m.w, m.h, Ink.front, s)
    cy = y + (m.h - m.inner_h) / 2
    rx = x + m.pad
    ry = cy + (m.inner_h - m.rec) / 2
    d.rectangle(
        [rx, ry, rx + m.rec, ry + m.rec],
        fill=Ink.record,
        outline=Ink.label,
        width=stroke_px(s),
    )
    tx = rx + m.rec + 8 * s
    d.text((tx, cy + (m.inner_h - m.th) / 2), timer, font=timer_f, fill=Ink.secondary)
    wx = tx + m.tw + m.gap
    wy = cy + (m.inner_h - m.wave_h) / 2
    wave = draw_waveform(d, wx, wy, m.wave_w, m.wave_h, s)
    if chip is not None:
        cx0 = wx + m.wave_w + m.gap
        ch = 18 * s
        cw = m.chip_w
        cy0 = cy + (m.inner_h - ch) / 2
        d.rectangle([cx0, cy0, cx0 + cw, cy0 + ch], outline=Ink.label, width=stroke_px(s), fill=Ink.front)
        cf = font(10 * s)
        label = str(chip)
        lw, lh = text_size(d, label, cf)
        gx = cx0 + 5 * s
        gy = cy0 + 4 * s
        d.rectangle([gx, gy, gx + 8 * s, gy + 8 * s], outline=Ink.label, width=max(1, int(round(s))))
        d.rectangle(
            [gx + 2 * s, gy + 2 * s, gx + 6 * s, gy + 6 * s],
            outline=Ink.hairline,
            width=max(1, int(round(s / 2))),
        )
        d.text((cx0 + cw - 5 * s - lw, cy0 + (ch - lh) / 2), label, font=cf, fill=Ink.label)
    record = (int(rx + m.rec / 2), int(ry + m.rec / 2))
    return Island(m.w, m.h, record, wave)


def draw_capture_tile(d: ImageDraw.ImageDraw, x: float, y: float, side: float, s: float) -> None:
    pane(d, x, y, side, side, Ink.fill, s)
    st = stroke_px(s)
    inset = 8 * s
    d.rectangle(
        [x + inset, y + inset, x + side - inset, y + side * 0.45],
        fill=Ink.front,
        outline=Ink.label,
        width=st,
    )
    d.rectangle(
        [x + inset, y + side * 0.52, x + side * 0.55, y + side - inset],
        fill=Ink.front,
        outline=Ink.label,
        width=st,
    )
    d.rectangle(
        [x + side * 0.6, y + side * 0.52, x + side - inset, y + side - inset],
        fill=Ink.record,
        outline=Ink.label,
        width=st,
    )


def render_banner() -> tuple[Image.Image, Island]:
    s = S
    W, H = int(920 * s), int(200 * s)
    img = Image.new("RGB", (W, H), Ink.window)
    d = ImageDraw.Draw(img)

    mark = 52 * s
    mx, my = 40 * s, (H - mark) / 2 - 4 * s
    draw_mark(d, mx, my, mark, s)

    wf = font(26 * s)
    ww, wh = text_size(d, WORDMARK, wf)
    wx = mx + mark + bevel_px(s) + 16 * s
    wy = my + 2 * s
    d.text((wx, wy), WORDMARK, font=wf, fill=Ink.label)

    tf = font(12 * s)
    tw, _ = text_size(d, BANNER_TAG, tf)
    d.text((wx, wy + wh + 10 * s), BANNER_TAG, font=tf, fill=Ink.secondary)

    m = island_metrics(d, s, "0:12", 1)
    ix = W - 44 * s - m.w - bevel_px(s)
    iy = (H - m.h) / 2
    if ix < wx + max(ww, tw) + 16 * s:
        raise SystemExit("banner island overlaps the wordmark")
    island = draw_island(d, ix, iy, s, timer="0:12", chip=1)
    return img, island


def render_demo() -> tuple[Image.Image, Island]:
    s = S
    W, H = int(920 * s), int(420 * s)
    img = Image.new("RGB", (W, H), Ink.window)
    d = ImageDraw.Draw(img)

    m = island_metrics(d, s, "0:12", 1)
    ix = (W - m.w) / 2
    iy = 72 * s
    island = draw_island(d, ix, iy, s, timer="0:12", chip=1)

    lines = ("okay so the save button", "should go on the left")
    lf = font(16 * s)
    ly = iy + m.h + bevel_px(s) + 36 * s
    for line in lines:
        lw, lh = text_size(d, line, lf)
        d.text(((W - lw) / 2, ly), line, font=lf, fill=Ink.label)
        ly += lh + 10 * s

    tile = 96 * s
    tile_y = ly + 20 * s
    draw_capture_tile(d, (W - tile) / 2, tile_y, tile, s)

    cf = font(11 * s)
    cw, ch = text_size(d, DEMO_CAPTION, cf)
    cap_y = H - 36 * s
    if tile_y + tile + bevel_px(s) + 16 * s > cap_y:
        raise SystemExit("demo tile collides with the caption")
    d.text(((W - cw) / 2, cap_y), DEMO_CAPTION, font=cf, fill=Ink.secondary)
    if ch <= 0:
        raise SystemExit("demo caption missing")
    return img, island


def render_social(s: float) -> Image.Image:
    W, H = int(1280 * s), int(640 * s)
    img = Image.new("RGB", (W, H), Ink.window)
    d = ImageDraw.Draw(img)
    side = 104 * s
    word_f = font(36 * s)
    pitch_f = font(18 * s)
    _, wh = text_size(d, WORDMARK, word_f)
    pw, ph = text_size(d, PITCH, pitch_f)
    if pw > W - 80 * s:
        raise SystemExit("social pitch does not fit")
    gap_m = 28 * s
    gap_p = 16 * s
    block = side + bevel_px(s) + gap_m + wh + gap_p + ph
    top = (H - block) / 2
    draw_mark(d, (W - side) / 2, top, side, s)
    y = top + side + bevel_px(s) + gap_m
    ww, _ = text_size(d, WORDMARK, word_f)
    d.text(((W - ww) / 2, y), WORDMARK, font=word_f, fill=Ink.label)
    y += wh + gap_p
    d.text(((W - pw) / 2, y), PITCH, font=pitch_f, fill=Ink.secondary)
    return img


def _counts(img: Image.Image) -> tuple[int, int, int, int]:
    raw = img.tobytes()
    black = light = red = cyan = 0
    for i in range(0, len(raw), 3):
        r = raw[i]
        g = raw[i + 1]
        b = raw[i + 2]
        if r < 16 and g < 16 and b < 16:
            black += 1
        if r >= 230 and g >= 230 and b >= 230:
            light += 1
        if r > 200 and g < 80 and b < 90:
            red += 1
        if r < 80 and g > 160 and b > 160:
            cyan += 1
    return black, light, red, cyan


def assert_graphite(
    img: Image.Image,
    name: str,
    *,
    want_red: bool,
    island: Island | None = None,
) -> None:
    if img.mode != "RGB":
        raise SystemExit(f"{name} mode {img.mode}, want RGB")
    w, h = img.size
    corners = (
        img.getpixel((0, 0)),
        img.getpixel((w - 1, 0)),
        img.getpixel((0, h - 1)),
        img.getpixel((w - 1, h - 1)),
    )
    if any(px != Ink.window for px in corners):
        raise SystemExit(f"{name} corners {corners} are not window {Ink.window}")
    lo, hi = img.convert("L").getextrema()
    if lo == hi:
        raise SystemExit(f"{name} blank")
    black, light, red, cyan = _counts(img)
    total = w * h
    if black > total * 0.9:
        raise SystemExit(f"{name} mostly black ({black}/{total})")
    if light < 80:
        raise SystemExit(f"{name} missing light ink ({light})")
    if cyan:
        raise SystemExit(f"{name} has {cyan} cyan pixels")
    if want_red and red < 20:
        raise SystemExit(f"{name} missing record red ({red})")
    if island is not None:
        if img.getpixel(island.record) != Ink.record:
            raise SystemExit(f"{name} record sample {img.getpixel(island.record)}")
        if img.getpixel(island.wave) != Ink.label:
            raise SystemExit(f"{name} waveform sample {img.getpixel(island.wave)}")
    print(f"ok {name} {img.size} light={light} red={red} black={black}")


def assert_copy() -> None:
    if WORDMARK != "da transcribuh" or WORDMARK.endswith(("_", "-", "█", "▌")) or "_" in WORDMARK:
        raise SystemExit("wordmark has a cursor or underscore")
    if "_" in PITCH or PITCH.endswith(" "):
        raise SystemExit("pitch has a cursor")
    text = README.read_text(encoding="utf-8")
    if PITCH not in text:
        raise SystemExit("README is missing the social pitch")
    if "assets/brand/readme-banner.png" not in text:
        raise SystemExit("README is missing the banner path")
    if "assets/brand/mocks/readme-island-demo-dark.png" not in text:
        raise SystemExit("README is missing the demo path")


def save_rgb(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    check = Image.open(path)
    if check.mode != "RGB":
        raise SystemExit(f"{path} reopened as {check.mode}")


def main() -> None:
    assert DEPARTURE.exists(), DEPARTURE
    assert_copy()
    OUT_BRAND.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)

    banner, banner_island = render_banner()
    assert_graphite(banner, "banner", want_red=True, island=banner_island)
    save_rgb(banner, OUT_BRAND / "readme-banner.png")

    demo, demo_island = render_demo()
    assert_graphite(demo, "demo", want_red=True, island=demo_island)
    save_rgb(demo, OUT_MOCKS / "readme-island-demo-dark.png")

    social_1 = render_social(1)
    social_2 = render_social(2)
    assert_graphite(social_1, "social-1x", want_red=False)
    assert_graphite(social_2, "social-2x", want_red=False)
    save_rgb(social_1, OUT_BRAND / "social-preview.png")
    save_rgb(social_1, OUT_BRAND / "social-preview-1280x640.png")
    save_rgb(social_2, OUT_BRAND / "social-preview-2560x1280@2x.png")
    print("wrote banner, demo, social")


if __name__ == "__main__":
    main()
