#!/usr/bin/env python3
"""Minimal README visuals (light only): hero banner + island demo.

Hero: dt mark + wordmark + tagline | small recording island (not a busy window).
Demo: island floating on whitespace with transcript lines + one capture tile.
Departure Mono, 2pt stroke, 3pt black offset. No tabs / stats / settings chrome.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT_BRAND = ROOT / "assets" / "brand"
OUT_MOCKS = OUT_BRAND / "mocks"
OUT_ART = Path("/opt/cursor/artifacts")

S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)
RED = (237, 28, 36)  # #ED1C24
INK = (0, 0, 0)
MUTED = (102, 102, 102)
WHITE = (255, 255, 255)
FILL = (240, 240, 240)


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def text_size(d: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = d.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def pane(d: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float, fill=WHITE) -> None:
    d.rectangle([x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL], fill=INK)
    d.rectangle([x, y, x + w, y + h], fill=fill, outline=INK, width=STROKE)


def draw_dt_mark(d: ImageDraw.ImageDraw, x: float, y: float, side: float) -> None:
    pane(d, x, y, side, side, WHITE)
    f = font(side * 0.42)
    db = d.textbbox((0, 0), "d", font=f)
    dw, dh = db[2] - db[0], db[3] - db[1]
    tb = d.textbbox((0, 0), "t", font=f)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    pad_x, pad_y, gap = 5 * S, 4 * S, 4 * S
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = x + (side - total) / 2
    top = y + (side - max(dh, bh)) / 2
    d.text((left - db[0], top + (max(dh, bh) - dh) / 2 - db[1]), "d", font=f, fill=INK)
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    d.rectangle([bx, by, bx + bw, by + bh], fill=INK)
    d.text((bx + (bw - tw) / 2 - tb[0], by + (bh - th) / 2 - tb[1]), "t", font=f, fill=WHITE)


def draw_waveform(d: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float) -> None:
    """Ink comb — fixed decorative heights (not live audio)."""
    heights = [0.25, 0.55, 0.9, 0.45, 0.7, 1.0, 0.6, 0.85, 0.35, 0.75, 0.5, 0.95, 0.4, 0.65, 0.3]
    bar_w = max(2 * S, w / (len(heights) * 1.6))
    gap = bar_w * 0.55
    cx = x
    mid = y + h / 2
    for frac in heights:
        bh = max(2 * S, h * frac)
        d.rectangle([cx, mid - bh / 2, cx + bar_w, mid + bh / 2], fill=INK)
        cx += bar_w + gap
        if cx > x + w:
            break


def draw_island(
    d: ImageDraw.ImageDraw,
    x: float,
    y: float,
    *,
    timer: str = "0:12",
    chip: int | None = 1,
    scale: float = 1.0,
) -> tuple[float, float]:
    """Record square + timer | waveform | optional screenshot chip. Returns (w, h)."""
    ss = S * scale
    pad = 10 * ss
    rec = 10 * ss
    timer_f = font(12 * scale * S)
    tw, th = text_size(d, timer, timer_f)
    wave_w, wave_h = 88 * ss, 22 * ss
    chip_w = (36 * ss) if chip is not None else 0
    gap = 10 * ss
    inner_h = max(rec, th, wave_h, 18 * ss)
    h = pad * 2 + inner_h
    w = pad + rec + 8 * ss + tw + gap + wave_w + (gap + chip_w if chip is not None else 0) + pad

    pane(d, x, y, w, h, WHITE)
    cy = y + (h - inner_h) / 2
    # record
    d.rectangle([x + pad, cy + (inner_h - rec) / 2, x + pad + rec, cy + (inner_h - rec) / 2 + rec], fill=RED, outline=INK, width=max(1, int(STROKE * 0.5)))
    # timer
    tx = x + pad + rec + 8 * ss
    d.text((tx, cy + (inner_h - th) / 2), timer, font=timer_f, fill=MUTED)
    # waveform
    wx = tx + tw + gap
    draw_waveform(d, wx, cy + (inner_h - wave_h) / 2, wave_w, wave_h)
    # chip
    if chip is not None:
        cx0 = wx + wave_w + gap
        ch = 18 * ss
        cw = chip_w
        cy0 = cy + (inner_h - ch) / 2
        d.rectangle([cx0, cy0, cx0 + cw, cy0 + ch], outline=INK, width=STROKE, fill=WHITE)
        cf = font(10 * scale * S)
        label = str(chip)
        lw, lh = text_size(d, label, cf)
        # tiny screen glyph
        gx = cx0 + 5 * ss
        gy = cy0 + 4 * ss
        d.rectangle([gx, gy, gx + 8 * ss, gy + 8 * ss], outline=INK, width=max(1, int(S)))
        d.rectangle([gx + 2 * ss, gy + 2 * ss, gx + 6 * ss, gy + 6 * ss], outline=INK, width=1)
        d.text((cx0 + cw - 5 * ss - lw, cy0 + (ch - lh) / 2), label, font=cf, fill=INK)
    return w, h


def draw_capture_tile(d: ImageDraw.ImageDraw, x: float, y: float, side: float) -> None:
    """Simple picture tile (abstract UI crop)."""
    pane(d, x, y, side, side, FILL)
    # faux screenshot content
    inset = 8 * S
    d.rectangle(
        [x + inset, y + inset, x + side - inset, y + side * 0.45],
        fill=WHITE,
        outline=INK,
        width=STROKE,
    )
    d.rectangle(
        [x + inset, y + side * 0.52, x + side * 0.55, y + side - inset],
        fill=WHITE,
        outline=INK,
        width=STROKE,
    )
    d.rectangle(
        [x + side * 0.6, y + side * 0.52, x + side - inset, y + side - inset],
        fill=RED,
        outline=INK,
        width=STROKE,
    )


def render_banner() -> Image.Image:
    W, H = int(920 * S), int(200 * S)
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    mark = 52 * S
    mx, my = 40 * S, (H - mark) / 2 - 4 * S
    draw_dt_mark(d, mx, my, mark)

    word = "da transcribuh"
    wf = font(26 * S)
    ww, wh = text_size(d, word, wf)
    wx = mx + mark + BEVEL + 16 * S
    wy = my + 2 * S
    d.text((wx, wy), word, font=wf, fill=INK)

    tag = "talk. it types. drag if u want the picture too."
    d.text((wx, wy + wh + 10 * S), tag, font=font(12 * S), fill=MUTED)

    # Right: just the recording island (not a busy window / stats card)
    iw, ih = island_size(d)
    ix = W - 44 * S - iw - BEVEL
    iy = (H - ih) / 2
    draw_island(d, ix, iy, timer="0:12", chip=1)
    return img


def island_size(d: ImageDraw.ImageDraw, timer: str = "0:12", chip: int | None = 1) -> tuple[float, float]:
    ss = S
    pad = 10 * ss
    rec = 10 * ss
    tw, _ = text_size(d, timer, font(12 * S))
    wave_w = 88 * ss
    chip_w = (36 * ss) if chip is not None else 0
    gap = 10 * ss
    inner_h = max(rec, 22 * ss)
    h = pad * 2 + inner_h
    w = pad + rec + 8 * ss + tw + gap + wave_w + (gap + chip_w if chip is not None else 0) + pad
    return w, h


def render_demo() -> Image.Image:
    """Island + words + one tile on a quiet light canvas."""
    W, H = int(920 * S), int(420 * S)
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    iw, ih = island_size(d)
    ix = (W - iw) / 2
    iy = 72 * S
    draw_island(d, ix, iy, timer="0:12", chip=1)

    # Transcript lines under the island — talk. it types.
    lines = [
        "okay so the save button",
        "should go on the left",
    ]
    lf = font(16 * S)
    ly = iy + ih + BEVEL + 36 * S
    for line in lines:
        lw, lh = text_size(d, line, lf)
        d.text(((W - lw) / 2, ly), line, font=lf, fill=INK)
        ly += lh + 10 * S

    # One captured picture tile — grab the picture
    tile = 96 * S
    draw_capture_tile(d, (W - tile) / 2, ly + 20 * S, tile)

    cap = "talk. it types. grab the picture."
    cf = font(11 * S)
    cw, _ = text_size(d, cap, cf)
    d.text(((W - cw) / 2, H - 36 * S), cap, font=cf, fill=MUTED)
    return img


def assert_ok(img: Image.Image, name: str) -> None:
    lo, hi = img.convert("L").getextrema()
    if lo == hi:
        raise SystemExit(f"{name} blank")
    print(f"ok {name} {img.size}")


def main() -> None:
    assert DEPARTURE.exists(), DEPARTURE
    OUT_BRAND.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    OUT_ART.mkdir(parents=True, exist_ok=True)

    banner = render_banner()
    assert_ok(banner, "banner")
    banner.save(OUT_BRAND / "readme-banner.png")
    banner.save(OUT_ART / "readme-banner-island-2x.png")
    banner.resize((920, int(banner.height / S)), Image.Resampling.LANCZOS).save(
        OUT_ART / "readme-banner-island.png"
    )

    demo = render_demo()
    assert_ok(demo, "demo")
    demo.save(OUT_MOCKS / "readme-island-demo-light.png")
    demo.save(OUT_ART / "readme-island-demo-light-2x.png")
    demo.resize((920, int(demo.height / S)), Image.Resampling.LANCZOS).save(
        OUT_ART / "readme-island-demo-light.png"
    )
    print("wrote readme-banner.png + mocks/readme-island-demo-light.png")


if __name__ == "__main__":
    main()
