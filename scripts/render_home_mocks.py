#!/usr/bin/env python3
"""Regenerate Settings Home README screenshots / paint mocks (light + graphite dark).

Reflects: folder tabs, inverted dark chrome (mark / keycaps / Start / tip tiles),
no yellow version badge, no hero tagline, no start-row helper, Get Started hidden
when complete, short tip columns.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT_SHOTS = ROOT / "assets" / "brand" / "screenshots"
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

W, H = 2040, 1400
SCALE = 2  # draw at 2× logical ~1020×700


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size=size)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


LIGHT = {
    "window": "#FFFFFF",
    "front": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "primary": "#000000",
    "on_primary": "#FFFFFF",
    "mark_face": "#FFFFFF",
    "mark_ink": "#000000",
    "mark_inv_face": "#000000",
    "mark_inv_ink": "#FFFFFF",
    "control": "#000000",
    "shelf": "#F0F0F0",
    "status": "#000000",
    "status_fg": "#FFFFFF",
}

DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#1A1A1C",
    "primary": "#3A3A3D",
    "on_primary": "#F2F2F2",
    "mark_face": "#3A3A3D",
    "mark_ink": "#F2F2F2",
    "mark_inv_face": "#F2F2F2",
    "mark_inv_ink": "#3A3A3D",
    "control": "#F2F2F2",
    "shelf": "#353538",
    "status": "#1A1A1C",
    "status_fg": "#A8A8AD",
}


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, side: float, pal: dict) -> None:
    bevel = max(2, side * 0.07)
    # bevel
    draw.rectangle([x + bevel, y + bevel, x + side + bevel, y + side + bevel], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + side, y + side], fill=c(pal, "mark_face"), outline=c(pal, "mark_ink"), width=2)
    f = font(side * 0.42)
    # rough centered d + inverted t
    cx, cy = x + side / 2, y + side / 2
    d = "d"
    t = "t"
    db = draw.textbbox((0, 0), d, font=f)
    tb = draw.textbbox((0, 0), t, font=f)
    dw, dh = db[2] - db[0], db[3] - db[1]
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    gap = side * 0.04
    pad_x, pad_y = side * 0.06, side * 0.04
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = cx - total / 2
    top = cy - max(dh, bh) / 2
    draw.text((left - db[0], top + (max(dh, bh) - dh) / 2 - db[1]), d, font=f, fill=c(pal, "mark_ink"))
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    draw.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "mark_inv_face"))
    draw.text(
        (bx + (bw - tw) / 2 - tb[0], by + (bh - th) / 2 - tb[1]),
        t,
        font=f,
        fill=c(pal, "mark_inv_ink"),
    )


def draw_keycap(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float, label: str, pal: dict) -> None:
    draw.rectangle([x + 2, y + 2, x + w + 2, y + h + 2], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "control"), width=2)
    f = font(h * 0.45)
    bb = draw.textbbox((0, 0), label, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    draw.text((x + (w - tw) / 2 - bb[0], y + (h - th) / 2 - bb[1]), label, font=f, fill=c(pal, "label"))


def draw_tab(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float, title: str, selected: bool, pal: dict) -> None:
    face = c(pal, "front") if selected else c(pal, "fill")
    # trapezoid-ish via rectangle
    draw.rectangle([x, y + (0 if selected else 4), x + w, y + h], fill=face, outline=c(pal, "label"), width=2)
    if selected:
        draw.rectangle([x + 8, y + 2, x + w - 8, y + 5], fill=hex_rgb("#ED1C24"))
    f = font(18)
    bb = draw.textbbox((0, 0), title, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    ty = y + (h - th) / 2 + (0 if selected else 2)
    draw.text((x + (w - tw) / 2 - bb[0], ty - bb[1]), title, font=f, fill=c(pal, "label" if selected else "secondary"))


def render(pal: dict) -> Image.Image:
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)

    # title strip
    strip_h = 80
    d.rectangle([0, 0, W, strip_h], fill=c(pal, "window"))
    d.rectangle([0, strip_h - 4, W, strip_h], fill=c(pal, "label"))
    # traffic lights
    for i, col in enumerate(["#ED1C24", "#FFF200", "#22B14C"]):
        x = 36 + i * 36
        d.rectangle([x, 28, x + 22, 50], fill=hex_rgb(col), outline=c(pal, "label"), width=2)
    # wordmark
    wf = font(26)
    d.text((W / 2 - 110, 26), "da transcribuh", font=wf, fill=c(pal, "label"))
    d.rectangle([W / 2 + 120, 28, W / 2 + 132, 52], fill=c(pal, "label"))

    # folder shelf
    shelf_y = strip_h
    shelf_h = 76
    d.rectangle([0, shelf_y, W, shelf_y + shelf_h], fill=c(pal, "shelf"))
    d.rectangle([0, shelf_y + shelf_h - 2, W, shelf_y + shelf_h], fill=c(pal, "hairline"))
    tabs = ["Home", "History", "Recording", "Models", "General", "Sound", "Perf"]
    tx = 72
    for i, name in enumerate(tabs):
        tw = 140 if name != "Recording" else 170
        if i in (3, 4):  # group gaps before Models and General
            tx += 16
        draw_tab(d, tx, shelf_y + 18, tw, 52, name, selected=(i == 0), pal=pal)
        tx += tw + 4
    # search chip
    d.rectangle([W - 160, shelf_y + 28, W - 72, shelf_y + 58], fill=c(pal, "fill"), outline=c(pal, "control"), width=2)
    d.text((W - 148, shelf_y + 34), "⌕ ⌘K", font=font(18), fill=c(pal, "secondary"))

    # content front
    content_top = shelf_y + shelf_h
    status_h = 64
    d.rectangle([0, content_top, W, H - status_h], fill=c(pal, "front"))

    # hero mark + wordmark (no yellow badge / tagline)
    mx, my = 120, content_top + 56
    draw_mark(d, mx, my, 96, pal)
    d.text((mx + 120, my + 28), "da transcribuh", font=font(40), fill=c(pal, "label"))

    # start row
    row_y = my + 140
    d.rectangle([120, row_y - 24, W - 120, row_y - 22], fill=c(pal, "hairline"))
    d.rectangle([120, row_y + 10, 140, row_y + 30], fill=hex_rgb("#ED1C24"), outline=c(pal, "label"), width=1)
    d.text((152, row_y + 6), "Start a session", font=font(26), fill=c(pal, "label"))
    # keycaps
    kx = W - 520
    for label, ww in (("⌃", 48), ("⌥", 48), ("Space", 110)):
        draw_keycap(d, kx, row_y, ww, 48, label, pal)
        kx += ww + 12
    # Start button
    bx, by, bw, bh = kx + 8, row_y, 130, 52
    d.rectangle([bx + 6, by + 6, bx + bw + 6, by + bh + 6], fill=hex_rgb("#ED1C24"))
    d.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "primary"), outline=c(pal, "control"), width=2)
    d.rectangle([bx + 16, by + 20, bx + 28, by + 32], fill=hex_rgb("#ED1C24"), outline=c(pal, "on_primary"), width=1)
    d.text((bx + 40, by + 12), "Start", font=font(24), fill=c(pal, "on_primary"))

    # stats
    sy = row_y + 110
    accents = ["#3F48CC", "#FF7F27", "#A349A4", "#22B14C"]
    labels = [("172", "SESSIONS"), ("50", "TILES"), ("3138", "WORDS"), ("29", "MINUTES")]
    gap = (W - 240) / 4
    for i, (num, lab) in enumerate(labels):
        x = 120 + i * gap
        d.text((x, sy), num, font=font(56), fill=c(pal, "label"))
        d.text((x, sy + 70), lab, font=font(20), fill=c(pal, "secondary"))
        d.rectangle([x, sy + 100, x + 160, sy + 108], fill=hex_rgb(accents[i]), outline=c(pal, "label"), width=1)

    # tips (no long helper on capture; path + Show on folder) — Get Started omitted (complete)
    ty = sy + 160
    for i, (glyph, title, detail) in enumerate(
        [
            ("[ ]", "Talk, or drag to capture", None),
            ("[=]", "Sessions folder", "~/Documents/PromptAnnotator/Sessions"),
        ]
    ):
        x = 120 + i * 520
        # tip tile
        d.rectangle([x + 4, ty + 4, x + 96 + 4, ty + 96 + 4], fill=c(pal, "bevel"))
        d.rectangle([x, ty, x + 96, ty + 96], fill=c(pal, "front"), outline=c(pal, "control"), width=3)
        d.text((x + 28, ty + 28), glyph, font=font(28), fill=c(pal, "label"))
        d.text((x, ty + 120), title, font=font(24), fill=c(pal, "label"))
        if detail:
            d.text((x, ty + 160), detail, font=font(18), fill=c(pal, "secondary"))
            # Show button
            d.rectangle([x + 2, ty + 200 + 2, x + 90 + 2, ty + 236 + 2], fill=c(pal, "bevel"))
            d.rectangle([x, ty + 200, x + 90, ty + 236], fill=c(pal, "front"), outline=c(pal, "control"), width=2)
            d.text((x + 18, ty + 206), "Show", font=font(18), fill=c(pal, "label"))

    # status bar
    d.rectangle([0, H - status_h, W, H], fill=c(pal, "status"))
    sf = font(20)
    d.text((36, H - 44), "■ idle    small.en_217MB    172 sessions    ⌃⌥Space", font=sf, fill=c(pal, "status_fg"))
    d.text((W - 220, H - 44), "0.9.0 beta (2)", font=sf, fill=c(pal, "status_fg"))
    return img


def main() -> None:
    if not FONT.exists():
        raise SystemExit(f"missing font: {FONT}")
    light = render(LIGHT)
    dark = render(DARK)
    OUT_SHOTS.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    light.save(OUT_SHOTS / "settings-home-light.png", "PNG")
    dark.save(OUT_SHOTS / "settings-home-dark.png", "PNG")
    light.save(OUT_MOCKS / "home-paint-light.png", "PNG")
    dark.save(OUT_MOCKS / "home-paint-dark.png", "PNG")
    print("wrote settings-home + home-paint light/dark")


if __name__ == "__main__":
    main()
