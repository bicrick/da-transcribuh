#!/usr/bin/env python3
"""Regenerate Settings Home README screenshots / paint mocks (light + graphite dark).

Faithful to the in-app Home layout: folder tabs with per-tab accents, mark + wordmark
(no yellow badge / tagline), Start row with keycaps + inverted Start, 4-col neutral
stats (full-width rules, thousands separators), Get Started checklist, tip tiles.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT_SHOTS = ROOT / "assets" / "brand" / "screenshots"
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

W, H = 2040, 1400


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
    "stat_rule": "#000000",
    "tile": "#FFFFFF",
    "on_tile": "#000000",
}

DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#1A1A1C",
    "primary": "#F2F2F2",
    "on_primary": "#2C2C2E",
    "mark_face": "#3A3A3D",
    "mark_ink": "#F2F2F2",
    "mark_inv_face": "#F2F2F2",
    "mark_inv_ink": "#3A3A3D",
    "control": "#F2F2F2",
    "shelf": "#353538",
    "status": "#1A1A1C",
    "status_fg": "#A8A8AD",
    "stat_rule": "#A8A8AD",
    "tile": "#3A3A3D",
    "on_tile": "#F2F2F2",
}

TAB_ACCENTS = {
    "Home": "#ED1C24",
    "History": "#3F48CC",
    "Recording": "#FF7F27",
    "Models": "#A349A4",
    "General": "#22B14C",
    "Sound": "#008080",
    "Perf": "#FFAEC9",
}


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, side: float, pal: dict) -> None:
    bevel = max(2, side * 0.07)
    draw.rectangle([x + bevel, y + bevel, x + side + bevel, y + side + bevel], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + side, y + side], fill=c(pal, "mark_face"), outline=c(pal, "mark_ink"), width=2)
    f = font(side * 0.42)
    cx, cy = x + side / 2, y + side / 2
    db = draw.textbbox((0, 0), "d", font=f)
    tb = draw.textbbox((0, 0), "t", font=f)
    dw, dh = db[2] - db[0], db[3] - db[1]
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    gap = side * 0.04
    pad_x, pad_y = side * 0.06, side * 0.04
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = cx - total / 2
    top = cy - max(dh, bh) / 2
    draw.text((left - db[0], top + (max(dh, bh) - dh) / 2 - db[1]), "d", font=f, fill=c(pal, "mark_ink"))
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    draw.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "mark_inv_face"))
    draw.text(
        (bx + (bw - tw) / 2 - tb[0], by + (bh - th) / 2 - tb[1]),
        "t",
        font=f,
        fill=c(pal, "mark_inv_ink"),
    )


def draw_keycap(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float, label: str, pal: dict) -> None:
    draw.rectangle([x + 2, y + 2, x + w + 2, y + h + 2], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "control"), width=2)
    f = font(h * 0.42)
    tw, th = text_size(draw, label, f)
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), label, font=f, fill=c(pal, "label"))


def draw_tab(
    draw: ImageDraw.ImageDraw,
    x: float,
    y: float,
    w: float,
    h: float,
    title: str,
    selected: bool,
    accent: str,
    pal: dict,
) -> None:
    face = c(pal, "front") if selected else c(pal, "fill")
    top = y if selected else y + 4
    draw.rectangle([x, top, x + w, y + h], fill=face, outline=c(pal, "label"), width=2)
    # Accent stripe / tick
    inset = 10 if selected else 14
    ay = top + (1 if selected else 2)
    ah = 2 if selected else 1
    accent_rgb = hex_rgb(accent)
    if selected:
        draw.rectangle([x + inset, ay, x + w - inset, ay + ah], fill=accent_rgb)
    else:
        # Quiet tick — muted
        muted = tuple(int(v * 0.45 + (c(pal, "fill")[i] * 0.55)) for i, v in enumerate(accent_rgb))
        draw.rectangle([x + inset, ay, x + w - inset, ay + ah], fill=muted)
    f = font(18)
    tw, th = text_size(draw, title, f)
    ty = top + (h - (0 if selected else 4) - th) / 2
    draw.text((x + (w - tw) / 2, ty), title, font=f, fill=c(pal, "label" if selected else "secondary"))


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont, width: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        trial = word if not cur else f"{cur} {word}"
        if text_size(draw, trial, f)[0] <= width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def render(pal: dict) -> Image.Image:
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)

    strip_h = 80
    d.rectangle([0, 0, W, strip_h], fill=c(pal, "window"))
    d.rectangle([0, strip_h - 4, W, strip_h], fill=c(pal, "label"))
    for i, col in enumerate(["#ED1C24", "#FFF200", "#22B14C"]):
        x = 36 + i * 36
        d.rectangle([x, 28, x + 22, 50], fill=hex_rgb(col), outline=c(pal, "label"), width=2)
    wf = font(26)
    tw, _ = text_size(d, "da transcribuh", wf)
    d.text(((W - tw) / 2, 26), "da transcribuh", font=wf, fill=c(pal, "label"))
    d.rectangle([(W + tw) / 2 + 8, 28, (W + tw) / 2 + 20, 52], fill=c(pal, "label"))

    shelf_y = strip_h
    shelf_h = 76
    d.rectangle([0, shelf_y, W, shelf_y + shelf_h], fill=c(pal, "shelf"))
    d.rectangle([0, shelf_y + shelf_h - 2, W, shelf_y + shelf_h], fill=c(pal, "hairline"))
    tabs = ["Home", "History", "Recording", "Models", "General", "Sound", "Perf"]
    tx = 72
    for i, name in enumerate(tabs):
        twid = 170 if name == "Recording" else 140
        if i in (3, 4):
            tx += 16
        draw_tab(d, tx, shelf_y + 18, twid, 52, name, selected=(i == 0), accent=TAB_ACCENTS[name], pal=pal)
        tx += twid + 4
    # ⌘K chip
    d.rectangle([W - 160, shelf_y + 28, W - 72, shelf_y + 58], fill=c(pal, "fill"), outline=c(pal, "control"), width=2)
    d.text((W - 148, shelf_y + 34), "⌕ ⌘K", font=font(18), fill=c(pal, "secondary"))

    content_top = shelf_y + shelf_h
    status_h = 64
    d.rectangle([0, content_top, W, H - status_h], fill=c(pal, "front"))

    # Hero — mark + wordmark only
    mx, my = 120, content_top + 56
    draw_mark(d, mx, my, 96, pal)
    d.text((mx + 120, my + 28), "da transcribuh", font=font(40), fill=c(pal, "label"))

    # Start row
    row_y = my + 140
    d.rectangle([120, row_y - 24, W - 120, row_y - 22], fill=c(pal, "hairline"))
    d.rectangle([120, row_y + 10, 140, row_y + 30], fill=hex_rgb("#ED1C24"), outline=c(pal, "label"), width=1)
    d.text((152, row_y + 6), "Start a session", font=font(26), fill=c(pal, "label"))
    kx = W - 520
    for label, ww in (("⌃", 48), ("⌥", 48), ("Space", 110)):
        draw_keycap(d, kx, row_y, ww, 48, label, pal)
        kx += ww + 12
    bx, by, bw, bh = kx + 8, row_y, 130, 52
    d.rectangle([bx + 6, by + 6, bx + bw + 6, by + bh + 6], fill=hex_rgb("#ED1C24"))
    d.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "primary"), outline=c(pal, "control"), width=2)
    d.rectangle([bx + 16, by + 20, bx + 28, by + 32], fill=hex_rgb("#ED1C24"), outline=c(pal, "on_primary"), width=1)
    d.text((bx + 40, by + 12), "Start", font=font(24), fill=c(pal, "on_primary"))

    # Stats — neutral full-column rules, thousands separator
    sy = row_y + 110
    labels = [("172", "SESSIONS"), ("50", "TILES"), ("3,138", "WORDS"), ("29", "MINUTES")]
    gap = (W - 240) / 4
    for i, (num, lab) in enumerate(labels):
        x = 120 + i * gap
        col_w = gap - 32
        d.text((x, sy), num, font=font(56), fill=c(pal, "label"))
        d.text((x, sy + 70), lab, font=font(20), fill=c(pal, "secondary"))
        d.rectangle([x, sy + 100, x + col_w, sy + 108], fill=c(pal, "stat_rule"), outline=c(pal, "label"), width=1)

    # Get Started (as-is)
    gy = sy + 150
    d.text((120, gy), "GET STARTED", font=font(20), fill=c(pal, "label"))
    d.rectangle([120, gy + 36, W - 120, gy + 38], fill=c(pal, "hairline"))
    d.text((120, gy + 52), "3 OF 3 DONE", font=font(18), fill=c(pal, "label"))
    bar_x, bar_y, bar_w = 280, gy + 56, W - 400
    d.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 16], outline=c(pal, "label"), width=2)
    d.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 16], fill=hex_rgb("#B5E61D"))
    d.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 16], outline=c(pal, "label"), width=2)

    items = [
        ("Permissions", "Screen Recording, Microphone, and Accessibility are on."),
        ("Speech model", "Balanced (small.en_217MB) is on this Mac."),
        ("First take", "172 sessions in History."),
    ]
    iy = gy + 90
    for title, detail in items:
        # check
        d.rectangle([120, iy, 152, iy + 32], fill=hex_rgb("#22B14C"), outline=c(pal, "label"), width=2)
        d.text((126, iy + 4), "✓", font=font(20), fill=hex_rgb("#000000"))
        d.text((168, iy), title, font=font(24), fill=c(pal, "label"))
        d.text((168, iy + 34), detail, font=font(18), fill=c(pal, "secondary"))
        d.rectangle([120, iy + 70, W - 120, iy + 71], fill=c(pal, "hairline"))
        iy += 90

    # Tips — two equal columns
    ty = iy + 20
    tip_w = (W - 240 - 32) / 2
    tips = [
        (
            "viewfinder",
            "Talk, or drag to capture",
            "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.",
            False,
        ),
        (
            "folder",
            "Sessions folder",
            "~/Documents/PromptAnnotator/Sessions",
            True,
        ),
    ]
    for i, (glyph, title, detail, show_btn) in enumerate(tips):
        x = 120 + i * (tip_w + 32)
        d.rectangle([x + 4, ty + 4, x + 96 + 4, ty + 96 + 4], fill=c(pal, "bevel"))
        d.rectangle([x, ty, x + 96, ty + 96], fill=c(pal, "tile"), outline=c(pal, "control"), width=3)
        # Simple glyph marks
        if glyph == "viewfinder":
            d.rectangle([x + 28, ty + 28, x + 68, ty + 68], outline=c(pal, "on_tile"), width=3)
            for cx, cy in ((x + 28, ty + 28), (x + 68, ty + 28), (x + 28, ty + 68), (x + 68, ty + 68)):
                d.rectangle([cx - 4, cy - 4, cx + 4, cy + 4], fill=c(pal, "on_tile"))
        else:
            d.rectangle([x + 28, ty + 36, x + 68, ty + 68], outline=c(pal, "on_tile"), width=3)
            d.rectangle([x + 36, ty + 28, x + 60, ty + 40], outline=c(pal, "on_tile"), width=2)
        d.text((x, ty + 120), title, font=font(24), fill=c(pal, "label"))
        cf = font(18)
        lines = wrap(d, detail, cf, tip_w - 8)
        ly = ty + 160
        for line in lines[:4]:
            d.text((x, ly), line, font=cf, fill=c(pal, "secondary"))
            ly += 26
        if show_btn:
            d.rectangle([x + 2, ly + 10, x + 90 + 2, ly + 46], fill=c(pal, "bevel"))
            d.rectangle([x, ly + 8, x + 90, ly + 44], fill=c(pal, "front"), outline=c(pal, "control"), width=2)
            d.text((x + 18, ly + 14), "Show", font=font(18), fill=c(pal, "label"))

    # Status
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
