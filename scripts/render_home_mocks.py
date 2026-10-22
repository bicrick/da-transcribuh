#!/usr/bin/env python3
"""Regenerate Settings Home README screenshots / paint mocks (light + graphite dark).

Matches the real app: angled FolderTabShape geometry (flare=5, corner r=3),
seamless selected tab (hairline interrupted, Ink.front merge), per-tab Paint
stripes, Departure Mono chrome, and DejaVu Sans for ⌃⌥⌘ glyphs.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
# Keycap / status symbols — Departure lacks ⌃⌥⌘; DejaVu covers them.
SYMBOL = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
OUT_SHOTS = ROOT / "assets" / "brand" / "screenshots"
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

W, H = 2040, 1400
# Logical ~1020×700 at 2×
S = 2.0

# FolderTabShape constants (Swift points → mock pixels via S)
FLARE = 5 * S
CORNER_R = 3 * S
TAB_H = 30 * S
SHELF_TOP_PAD = 8 * S
UNSELECTED_INSET = 3 * S
PAGE_SIDE = 36 * S
TAB_GROUP_GAP = 8 * S
TAB_INNER_GAP = 2 * S


def font_departure(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def font_symbol(size: float) -> ImageFont.FreeTypeFont:
    if SYMBOL.exists():
        return ImageFont.truetype(str(SYMBOL), size=size)
    return font_departure(size)


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
    "status": "#1A1A1C",
    "status_fg": "#A8A8AD",
    "stat_rule": "#A8A8AD",
    "tile": "#3A3A3D",
    "on_tile": "#F2F2F2",
}

TABS = [
    ("Home", "#ED1C24"),
    ("History", "#3F48CC"),
    ("Recording", "#FF7F27"),
    ("Models", "#A349A4"),
    ("General", "#22B14C"),
    ("Sound", "#008080"),
    ("Perf", "#FFAEC9"),
]
# Group breaks before Models (index 3) and General (index 4) — matches tabGroups.
GROUP_BEFORE = {3, 4}


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def measure_tab_width(draw: ImageDraw.ImageDraw, title: str) -> float:
    f = font_departure(11 * S)
    tw, _ = text_size(draw, title, f)
    # icon (~10pt) + gap + label + horizontal pad space3*2
    return 10 * S + 5 * S + tw + 12 * S * 2


def folder_tab_polygon(x: float, y: float, w: float, h: float) -> list[tuple[float, float]]:
    """Match FolderTabShape: flare shoulders, rounded top corners."""
    flare, r = FLARE, CORNER_R
    # Approximate quad curves with short segments for PIL polygon
    def corner(cx: float, cy: float, from_angle: float, to_angle: float) -> list[tuple[float, float]]:
        import math
        pts = []
        for i in range(5):
            t = i / 4
            a = from_angle + (to_angle - from_angle) * t
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        return pts

    import math
    pts: list[tuple[float, float]] = []
    pts.append((x, y + h))  # bottom-left
    pts.append((x + flare, y + r))
    # top-left corner
    pts.extend(corner(x + flare + r, y + r, math.pi, math.pi * 1.5))
    pts.append((x + w - flare - r, y))
    # top-right corner
    pts.extend(corner(x + w - flare - r, y + r, math.pi * 1.5, math.pi * 2))
    pts.append((x + w - flare, y + r))
    pts.append((x + w, y + h))  # bottom-right
    return pts


def draw_folder_tab(
    draw: ImageDraw.ImageDraw,
    x: float,
    y: float,
    w: float,
    h: float,
    title: str,
    accent: str,
    selected: bool,
    pal: dict,
) -> None:
    face = c(pal, "front") if selected else c(pal, "fill")
    poly = folder_tab_polygon(x, y, w, h)
    draw.polygon(poly, fill=face)
    # Stroke — for selected, omit bottom edge (seamless with page).
    if selected:
        # left slant + top + right slant only
        stroke = poly[:-1]  # drop closing to bottom-left via bottom edge
        # redraw open path as line segments excluding bottom
        for i in range(len(poly) - 2):
            draw.line([poly[i], poly[i + 1]], fill=c(pal, "label"), width=max(2, int(S)))
        # left bottom vertical-ish: poly[0] to poly[1], right poly[-2] to poly[-1]
        draw.line([poly[0], poly[1]], fill=c(pal, "label"), width=max(2, int(S)))
        draw.line([poly[-2], poly[-1]], fill=c(pal, "label"), width=max(2, int(S)))
    else:
        draw.line(poly + [poly[0]], fill=c(pal, "label"), width=max(2, int(S)))

    # Accent stripe / tick along top
    inset = (10 if selected else 14) * S
    ay = y + (1 if selected else 2) * S
    ah = (2 if selected else 1) * S
    accent_rgb = hex_rgb(accent)
    if not selected:
        fill_rgb = c(pal, "fill")
        accent_rgb = tuple(int(a * 0.45 + f * 0.55) for a, f in zip(accent_rgb, fill_rgb))
    draw.rectangle([x + inset, ay, x + w - inset, ay + ah], fill=accent_rgb)

    # Label (icon omitted in mock — title only for clarity at this scale, or draw house etc.)
    f = font_departure(11 * S)
    tw, th = text_size(draw, title, f)
    ty = y + (h - th) / 2 + (0 if selected else 1)
    draw.text((x + (w - tw) / 2, ty), title, font=f, fill=c(pal, "label" if selected else "secondary"))


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, side: float, pal: dict) -> None:
    bevel = max(2, side * 0.07)
    draw.rectangle([x + bevel, y + bevel, x + side + bevel, y + side + bevel], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + side, y + side], fill=c(pal, "mark_face"), outline=c(pal, "mark_ink"), width=max(2, int(S)))
    f = font_departure(side * 0.42)
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
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "control"), width=max(2, int(S)))
    # Use symbol font for ⌃⌥⌘; Departure for ASCII like "Space"
    use_sym = any(ord(ch) > 127 for ch in label)
    f = font_symbol(h * 0.42) if use_sym else font_departure(h * 0.42)
    tw, th = text_size(draw, label, f)
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), label, font=f, fill=c(pal, "label"))


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

    # Title strip
    strip_h = 40 * S
    d.rectangle([0, 0, W, strip_h], fill=c(pal, "window"))
    d.rectangle([0, strip_h - 2 * S, W, strip_h], fill=c(pal, "label"))
    for i, col in enumerate(["#ED1C24", "#FFF200", "#22B14C"]):
        x = 12 * S + i * 18 * S
        d.rectangle([x, 12 * S, x + 11 * S, 23 * S], fill=hex_rgb(col), outline=c(pal, "label"), width=max(1, int(S)))
    wf = font_departure(13 * S)
    tw, th = text_size(d, "da transcribuh", wf)
    d.text(((W - tw) / 2, (strip_h - th) / 2 - 2), "da transcribuh", font=wf, fill=c(pal, "label"))
    d.rectangle([(W + tw) / 2 + 4, strip_h / 2 - 6, (W + tw) / 2 + 4 + 6 * S, strip_h / 2 + 6], fill=c(pal, "label"))

    # Folder shelf
    shelf_y = strip_h
    shelf_h = SHELF_TOP_PAD + TAB_H
    d.rectangle([0, shelf_y, W, shelf_y + shelf_h], fill=c(pal, "fill"))

    # Measure + place tabs
    widths = [measure_tab_width(d, name) for name, _ in TABS]
    tx = PAGE_SIDE
    tab_rects: list[tuple[float, float, float, float, bool, str, str]] = []
    tab_bottom = shelf_y + shelf_h
    for i, ((name, accent), twid) in enumerate(zip(TABS, widths)):
        if i in GROUP_BEFORE:
            tx += TAB_GROUP_GAP
        selected = i == 0
        # Selected bleeds 1pt into content; unselected inset from bottom
        if selected:
            ty = tab_bottom - TAB_H - 1 * S  # bleed 1pt past shelf
            th = TAB_H + 1 * S
        else:
            ty = tab_bottom - (TAB_H - UNSELECTED_INSET)
            th = TAB_H - UNSELECTED_INSET
        tab_rects.append((tx, ty, twid, th, selected, name, accent))
        tx += twid + TAB_INNER_GAP

    selected_gap = tab_rects[0]
    gap_left = selected_gap[0]
    gap_right = selected_gap[0] + selected_gap[2]

    # Hairline with gap under selected tab
    hy = shelf_y + shelf_h - 1
    d.line([(0, hy), (gap_left, hy)], fill=c(pal, "hairline"), width=max(1, int(S)))
    d.line([(gap_right, hy), (W, hy)], fill=c(pal, "hairline"), width=max(1, int(S)))

    # Draw tabs (selected last so it sits on top)
    for rect in sorted(tab_rects, key=lambda r: r[4]):  # unselected first
        x, y, w, h, selected, name, accent = rect
        draw_folder_tab(d, x, y, w, h, name, accent, selected, pal)
    # redraw selected on top
    x, y, w, h, selected, name, accent = tab_rects[0]
    draw_folder_tab(d, x, y, w, h, name, accent, True, pal)

    # ⌘K chip
    chip_f = font_symbol(10 * S)
    chip_label = "⌕ ⌘K"
    # search uses departure for ⌕ if needed — use combo
    cf1 = font_departure(11 * S)
    cf2 = font_symbol(10 * S)
    d.rectangle([W - PAGE_SIDE - 70 * S, shelf_y + 14 * S, W - PAGE_SIDE, shelf_y + 28 * S], fill=c(pal, "fill"), outline=c(pal, "control"), width=max(1, int(S)))
    d.text((W - PAGE_SIDE - 64 * S, shelf_y + 16 * S), "⌘K", font=cf2, fill=c(pal, "secondary"))

    # Content
    content_top = shelf_y + shelf_h
    status_h = 32 * S
    d.rectangle([0, content_top, W, H - status_h], fill=c(pal, "front"))
    # Cover hairline gap with front under selected tab bleed
    d.rectangle([gap_left + 1, hy, gap_right - 1, content_top + 2], fill=c(pal, "front"))
    # Redraw selected tab on top of that cover
    draw_folder_tab(d, x, y, w, h, name, accent, True, pal)

    # Hero
    mx, my = PAGE_SIDE, content_top + 28 * S
    mark_side = 48 * S
    draw_mark(d, mx, my, mark_side, pal)
    d.text((mx + mark_side + 16 * S, my + 12 * S), "da transcribuh", font=font_departure(20 * S), fill=c(pal, "label"))

    # Start row
    row_y = my + mark_side + 24 * S
    d.rectangle([PAGE_SIDE, row_y - 16 * S, W - PAGE_SIDE, row_y - 16 * S + 1], fill=c(pal, "hairline"))
    d.rectangle([PAGE_SIDE, row_y + 4 * S, PAGE_SIDE + 10 * S, row_y + 14 * S], fill=hex_rgb("#ED1C24"), outline=c(pal, "label"), width=1)
    d.text((PAGE_SIDE + 16 * S, row_y + 2 * S), "Start a session", font=font_departure(13 * S), fill=c(pal, "label"))

    kx = W - PAGE_SIDE - 280 * S
    for label, ww in (("⌃", 26 * S), ("⌥", 26 * S), ("Space", 56 * S)):
        draw_keycap(d, kx, row_y, ww, 26 * S, label, pal)
        kx += ww + 6 * S
    bx, by, bw, bh = kx + 8 * S, row_y - 2 * S, 72 * S, 30 * S
    d.rectangle([bx + 3 * S, by + 3 * S, bx + bw + 3 * S, by + bh + 3 * S], fill=hex_rgb("#ED1C24"))
    d.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "primary"), outline=c(pal, "control"), width=max(1, int(S)))
    d.rectangle([bx + 10 * S, by + 11 * S, bx + 18 * S, by + 19 * S], fill=hex_rgb("#ED1C24"), outline=c(pal, "on_primary"), width=1)
    d.text((bx + 24 * S, by + 6 * S), "Start", font=font_departure(13 * S), fill=c(pal, "on_primary"))

    # Stats
    sy = row_y + 48 * S
    labels = [("172", "SESSIONS"), ("50", "TILES"), ("3,138", "WORDS"), ("29", "MINUTES")]
    gap = (W - 2 * PAGE_SIDE) / 4
    for i, (num, lab) in enumerate(labels):
        x = PAGE_SIDE + i * gap
        col_w = gap - 16 * S
        d.text((x, sy), num, font=font_departure(28 * S), fill=c(pal, "label"))
        d.text((x, sy + 36 * S), lab, font=font_departure(11 * S), fill=c(pal, "secondary"))
        d.rectangle([x, sy + 52 * S, x + col_w, sy + 52 * S + 4 * S], fill=c(pal, "stat_rule"), outline=c(pal, "label"), width=1)

    # Get Started
    gy = sy + 80 * S
    d.text((PAGE_SIDE, gy), "GET STARTED", font=font_departure(11 * S), fill=c(pal, "label"))
    d.rectangle([PAGE_SIDE, gy + 20 * S, W - PAGE_SIDE, gy + 20 * S + 1], fill=c(pal, "hairline"))
    d.text((PAGE_SIDE, gy + 32 * S), "3 OF 3 DONE", font=font_departure(11 * S), fill=c(pal, "label"))
    bar_x = PAGE_SIDE + 120 * S
    bar_y = gy + 34 * S
    bar_w = W - PAGE_SIDE - bar_x
    d.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + 8 * S], fill=hex_rgb("#B5E61D"), outline=c(pal, "label"), width=max(2, int(S)))

    items = [
        ("Permissions", "Screen Recording, Microphone, and Accessibility are on."),
        ("Speech model", "Balanced (small.en_217MB) is on this Mac."),
        ("First take", "172 sessions in History."),
    ]
    iy = gy + 56 * S
    for title, detail in items:
        # green check box (drawn, not tofu)
        d.rectangle([PAGE_SIDE, iy, PAGE_SIDE + 16 * S, iy + 16 * S], fill=hex_rgb("#22B14C"), outline=c(pal, "label"), width=max(2, int(S)))
        # checkmark via lines
        d.line(
            [
                (PAGE_SIDE + 3 * S, iy + 8 * S),
                (PAGE_SIDE + 6 * S, iy + 12 * S),
                (PAGE_SIDE + 13 * S, iy + 4 * S),
            ],
            fill=hex_rgb("#000000"),
            width=max(2, int(S)),
        )
        d.text((PAGE_SIDE + 24 * S, iy - 2 * S), title, font=font_departure(13 * S), fill=c(pal, "label"))
        d.text((PAGE_SIDE + 24 * S, iy + 16 * S), detail, font=font_departure(11 * S), fill=c(pal, "secondary"))
        d.rectangle([PAGE_SIDE, iy + 36 * S, W - PAGE_SIDE, iy + 36 * S + 1], fill=c(pal, "hairline"))
        iy += 48 * S

    # Tips
    ty = iy + 16 * S
    tip_w = (W - 2 * PAGE_SIDE - 16 * S) / 2
    tips = [
        (
            "viewfinder",
            "Talk, or drag to capture",
            "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. A capture pastes the picture with the words.",
            False,
        ),
        ("folder", "Sessions folder", "~/Documents/PromptAnnotator/Sessions", True),
    ]
    for i, (glyph, title, detail, show_btn) in enumerate(tips):
        x = PAGE_SIDE + i * (tip_w + 16 * S)
        icon = 48 * S
        d.rectangle([x + 2 * S, ty + 2 * S, x + icon + 2 * S, ty + icon + 2 * S], fill=c(pal, "bevel"))
        d.rectangle([x, ty, x + icon, ty + icon], fill=c(pal, "tile"), outline=c(pal, "control"), width=max(2, int(S)))
        if glyph == "viewfinder":
            m = 12 * S
            d.rectangle([x + m, ty + m, x + icon - m, ty + icon - m], outline=c(pal, "on_tile"), width=max(2, int(S)))
        else:
            d.rectangle([x + 14 * S, ty + 18 * S, x + icon - 14 * S, ty + icon - 12 * S], outline=c(pal, "on_tile"), width=max(2, int(S)))
            d.rectangle([x + 18 * S, ty + 12 * S, x + icon - 18 * S, ty + 20 * S], outline=c(pal, "on_tile"), width=max(2, int(S)))
        d.text((x, ty + icon + 8 * S), title, font=font_departure(13 * S), fill=c(pal, "label"))
        cf = font_departure(11 * S)
        lines = wrap(d, detail, cf, tip_w - 4)
        ly = ty + icon + 28 * S
        for line in lines[:4]:
            d.text((x, ly), line, font=cf, fill=c(pal, "secondary"))
            ly += 16 * S
        if show_btn:
            d.rectangle([x + 2 * S, ly + 6 * S, x + 48 * S + 2 * S, ly + 28 * S], fill=c(pal, "bevel"))
            d.rectangle([x, ly + 4 * S, x + 48 * S, ly + 26 * S], fill=c(pal, "front"), outline=c(pal, "control"), width=max(1, int(S)))
            d.text((x + 10 * S, ly + 8 * S), "Show", font=font_departure(11 * S), fill=c(pal, "label"))

    # Status bar — proper glyphs via DejaVu
    d.rectangle([0, H - status_h, W, H], fill=c(pal, "status"))
    sf = font_departure(11 * S)
    sym = font_symbol(11 * S)
    d.text((18 * S, H - 22 * S), "■ idle", font=sf, fill=c(pal, "status_fg"))
    d.text((90 * S, H - 22 * S), "small.en_217MB", font=sf, fill=c(pal, "status_fg"))
    d.text((260 * S, H - 22 * S), "172 sessions", font=sf, fill=c(pal, "status_fg"))
    d.text((400 * S, H - 22 * S), "⌃⌥Space", font=sym, fill=c(pal, "status_fg"))
    ver = "0.9.0 beta (2)"
    vw, _ = text_size(d, ver, sf)
    d.text((W - 18 * S - vw, H - 22 * S), ver, font=sf, fill=c(pal, "status_fg"))
    return img


def main() -> None:
    if not DEPARTURE.exists():
        raise SystemExit(f"missing font: {DEPARTURE}")
    if not SYMBOL.exists():
        print("warn: DejaVu Sans missing; keycap symbols may tofu")
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
