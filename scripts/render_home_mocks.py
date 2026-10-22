#!/usr/bin/env python3
"""Regenerate Settings Home README screenshots / paint mocks (light + graphite dark).

Matches the real app: Paint FolderTabShape — square faces, Ink.stroke (2pt)
outlines, hard Ink.bevelOffset (3pt) ink strip on the RIGHT only (never below
the shelf). Continuous accent shelf joins selected sides at right angles.
Unselected: open-bottom muted accent outlines. Selection-invariant layout.
⌘K chip matches (square + right bevel). Departure Mono; DejaVu for ⌃⌥⌘.
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

W, H = 2040, 1560
# Logical ~1020×780 at 2× (bento Home needs a bit more height)
S = 2.0
CELL_GAP = 12 * S
# Ink.bevelOffset = 3pt → 6px at 2×
BEVEL = 3 * S

# Paint FolderTabShape constants (Swift points → mock pixels via S)
TAB_H = 30 * S
SHELF_TOP_PAD = 8 * S
PAGE_SIDE = 36 * S
TAB_GROUP_GAP = 8 * S
TAB_INNER_GAP = 2 * S
# Ink.stroke = 2pt → 4px at 2× (chrome outlines + shelf)
STROKE = int(2 * S)
# Internal separators only (Recent rows, wordmark rule)
HAIRLINE = max(1, int(S))


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

# Accents match Ink.tabStroke* light values (Appearance = purple).
TABS = [
    ("Home", "#ED1C24"),
    ("Appearance", "#A349A4"),
    ("History", "#3F48CC"),
    ("Models", "#FF7F27"),
    ("General", "#22B14C"),
    ("Sound", "#008080"),
    ("Perf", "#FFAEC9"),
]
# Dark lifted accents for graphite contrast on the continuous shelf stroke.
TABS_DARK_ACCENT = {
    "#ED1C24": "#FF5A5F",
    "#A349A4": "#C46BC5",
    "#3F48CC": "#6B73E0",
    "#FF7F27": "#FF9A4D",
    "#22B14C": "#3FD06A",
    "#008080": "#2AA8A8",
    "#FFAEC9": "#FFC0D6",
}
# Group breaks before Models (index 3) and General (index 4) — matches tabGroups.
GROUP_BEFORE = {3, 4}


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def measure_tab_face_width(draw: ImageDraw.ImageDraw, title: str) -> float:
    """Selection-invariant face width (label + pad). Bevel gutter is separate."""
    f = font_departure(11 * S)
    tw, _ = text_size(draw, title, f)
    return 10 * S + 5 * S + tw + 12 * S * 2


def measure_tab_width(draw: ImageDraw.ImageDraw, title: str, selected: bool = False) -> float:
    """Face + trailing bevel gutter (selection-invariant)."""
    del selected
    return measure_tab_face_width(draw, title) + BEVEL


def square_tab_outline(x: float, y: float, w: float, h: float) -> list[tuple[float, float]]:
    """Open-bottom square: bottom-left → top-left → top-right → bottom-right."""
    return [
        (x, y + h),
        (x, y),
        (x + w, y),
        (x + w, y + h),
    ]


def stroke_polyline(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], fill, width: int) -> None:
    if len(pts) < 2:
        return
    draw.line(pts, fill=fill, width=width, joint="miter")


def draw_right_bevel(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float, pal: dict) -> None:
    """Ink bevel strip on the RIGHT of the face — flush top/bottom with the face (not below shelf)."""
    draw.rectangle(
        [x + w, y, x + w + BEVEL, y + h],
        fill=c(pal, "bevel"),
    )


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
    """Square face + right ink bevel. `w` is face width (excludes bevel gutter)."""
    face = c(pal, "front") if selected else c(pal, "fill")
    outline = square_tab_outline(x, y, w, h)
    draw.polygon(outline + [outline[0]], fill=face)
    draw_right_bevel(draw, x, y, w, h, pal)
    if not selected:
        muted = tuple(int(a * 0.55 + f * 0.45) for a, f in zip(hex_rgb(accent), c(pal, "fill")))
        stroke_polyline(draw, outline, muted, STROKE)

    fnt = font_departure(11 * S)
    tw, th = text_size(draw, title, fnt)
    ty = y + (h - th) / 2
    draw.text(
        (x + (w - tw) / 2, ty),
        title,
        font=fnt,
        fill=c(pal, "label" if selected else "secondary"),
    )


def draw_continuous_shelf_stroke(
    draw: ImageDraw.ImageDraw,
    shelf_bottom: float,
    tab_x: float,
    tab_y: float,
    tab_w: float,
    tab_h: float,
    accent: tuple[int, int, int],
) -> None:
    """Full-width rule joined to selected square outline at crisp right angles."""
    # Pixel-center the stroke on the shelf / face edges (matches Swift SelectedTabShelfStroke).
    y = shelf_bottom
    top = tab_y + STROKE / 2
    left, right = tab_x, tab_x + tab_w
    outline = [
        (0, y),
        (left, y),
        (left, top),
        (right, top),
        (right, y),
        (W, y),
    ]
    stroke_polyline(draw, outline, accent, STROKE)


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, side: float, pal: dict) -> None:
    bevel = BEVEL
    draw.rectangle([x + bevel, y + bevel, x + side + bevel, y + side + bevel], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + side, y + side], fill=c(pal, "mark_face"), outline=c(pal, "mark_ink"), width=STROKE)
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
    draw.rectangle([x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
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


def draw_bento_cell(
    draw: ImageDraw.ImageDraw,
    x: float,
    y: float,
    w: float,
    h: float,
    title: str,
    pal: dict,
    trailing: str | None = None,
    compact: bool = False,
) -> tuple[float, float]:
    """Paint/Ink cell: face + Ink.stroke border + Ink.bevelOffset. Returns content origin (cx, cy)."""
    pad = (12 if compact else 16) * S
    # Bevel behind
    draw.rectangle(
        [x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL],
        fill=c(pal, "bevel"),
    )
    draw.rectangle(
        [x, y, x + w, y + h],
        fill=c(pal, "front"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    hf = font_departure(11 * S)
    draw.text((x + pad, y + pad), title, font=hf, fill=c(pal, "label"))
    if trailing:
        tw, th = text_size(draw, trailing, hf)
        draw.text(
            (x + w - pad - tw, y + pad),
            trailing,
            font=hf,
            fill=c(pal, "secondary"),
        )
    # Content starts below caption header
    content_y = y + pad + 14 * S + (8 if compact else 12) * S
    return x + pad, content_y


def render(pal: dict) -> Image.Image:
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)

    # Title strip — hairline rule under chrome (separator, not border)
    strip_h = 40 * S
    d.rectangle([0, 0, W, strip_h], fill=c(pal, "window"))
    d.rectangle([0, strip_h - HAIRLINE, W, strip_h], fill=c(pal, "label"))
    for i, col in enumerate(["#ED1C24", "#FFF200", "#22B14C"]):
        x = 12 * S + i * 18 * S
        d.rectangle([x, 12 * S, x + 11 * S, 23 * S], fill=hex_rgb(col), outline=c(pal, "label"), width=STROKE)
    wf = font_departure(13 * S)
    tw, th = text_size(d, "da transcribuh", wf)
    d.text(((W - tw) / 2, (strip_h - th) / 2 - 2), "da transcribuh", font=wf, fill=c(pal, "label"))
    d.rectangle([(W + tw) / 2 + 4, strip_h / 2 - 6, (W + tw) / 2 + 4 + 6 * S, strip_h / 2 + 6], fill=c(pal, "label"))

    # Folder shelf
    shelf_y = strip_h
    shelf_h = SHELF_TOP_PAD + TAB_H
    d.rectangle([0, shelf_y, W, shelf_y + shelf_h], fill=c(pal, "fill"))

    # Measure + place tabs (face width + bevel gutter; selection-invariant)
    tx = PAGE_SIDE
    # (x, y, face_w, h, selected, name, accent)
    tab_rects: list[tuple[float, float, float, float, bool, str, str]] = []
    tab_bottom = shelf_y + shelf_h
    for i, (name, accent) in enumerate(TABS):
        if i in GROUP_BEFORE:
            tx += TAB_GROUP_GAP
        selected = i == 0
        face_w = measure_tab_face_width(d, name)
        ty = tab_bottom - TAB_H
        tab_rects.append((tx, ty, face_w, TAB_H, selected, name, accent))
        tx += face_w + BEVEL + TAB_INNER_GAP

    # Content under shelf (selected fill merges into page)
    content_top = shelf_y + shelf_h
    status_h = 32 * S
    d.rectangle([0, content_top, W, H - status_h], fill=c(pal, "front"))

    # Unselected tabs first
    for rect in tab_rects:
        x, y, w, h, selected, name, accent = rect
        if not selected:
            draw_folder_tab(d, x, y, w, h, name, accent, False, pal)

    # Selected fill + continuous accent shelf stroke (square join)
    sx, sy, sw, sh, _, sname, saccent = tab_rects[0]
    draw_folder_tab(d, sx, sy, sw, sh, sname, saccent, True, pal)
    d.rectangle(
        [sx, tab_bottom - 1, sx + sw, tab_bottom + STROKE],
        fill=c(pal, "front"),
    )
    accent_hex = saccent
    if pal is DARK:
        accent_hex = TABS_DARK_ACCENT.get(saccent, saccent)
    draw_continuous_shelf_stroke(
        d, tab_bottom - STROKE / 2, sx, sy, sw, sh, hex_rgb(accent_hex)
    )
    draw_folder_tab(d, sx, sy, sw, sh, sname, saccent, True, pal)

    # ⌘K chip — square + right ink bevel
    cf2 = font_symbol(10 * S)
    chip_x = W - PAGE_SIDE - 70 * S - BEVEL
    chip_y = shelf_y + 14 * S
    chip_w, chip_h = 70 * S, 14 * S
    d.rectangle(
        [chip_x, chip_y, chip_x + chip_w, chip_y + chip_h],
        fill=c(pal, "fill"),
        outline=c(pal, "control"),
        width=STROKE,
    )
    draw_right_bevel(d, chip_x, chip_y, chip_w, chip_h, pal)
    d.text((chip_x + 6 * S, chip_y + 2 * S), "⌘K", font=cf2, fill=c(pal, "secondary"))

    # Hero
    mx, my = PAGE_SIDE, content_top + 28 * S
    mark_side = 48 * S
    draw_mark(d, mx, my, mark_side, pal)
    d.text((mx + mark_side + 16 * S, my + 12 * S), "da transcribuh", font=font_departure(20 * S), fill=c(pal, "label"))

    # Start row
    row_y = my + mark_side + 24 * S
    d.rectangle([PAGE_SIDE, row_y - 16 * S, W - PAGE_SIDE, row_y - 16 * S + HAIRLINE], fill=c(pal, "hairline"))
    d.rectangle([PAGE_SIDE, row_y + 4 * S, PAGE_SIDE + 10 * S, row_y + 14 * S], fill=hex_rgb("#ED1C24"), outline=c(pal, "label"), width=STROKE)
    d.text((PAGE_SIDE + 16 * S, row_y + 2 * S), "Start a session", font=font_departure(13 * S), fill=c(pal, "label"))

    kx = W - PAGE_SIDE - 280 * S
    for label, ww in (("⌃", 26 * S), ("⌥", 26 * S), ("Space", 56 * S)):
        draw_keycap(d, kx, row_y, ww, 26 * S, label, pal)
        kx += ww + 6 * S
    bx, by, bw, bh = kx + 8 * S, row_y - 2 * S, 72 * S, 30 * S
    d.rectangle([bx + BEVEL, by + BEVEL, bx + bw + BEVEL, by + bh + BEVEL], fill=hex_rgb("#ED1C24"))
    d.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "primary"), outline=c(pal, "control"), width=STROKE)
    d.rectangle([bx + 10 * S, by + 11 * S, bx + 18 * S, by + 19 * S], fill=hex_rgb("#ED1C24"), outline=c(pal, "on_primary"), width=STROKE)
    d.text((bx + 24 * S, by + 6 * S), "Start", font=font_departure(13 * S), fill=c(pal, "on_primary"))

    # —— Bento grid (completed Home; example data, clearly fake) ——
    content_left = PAGE_SIDE
    content_w = W - 2 * PAGE_SIDE
    # Account for bevel overhang on the right edge of the last cell in a row
    usable_w = content_w - BEVEL

    # Row 1: four equal stat cells
    sy = row_y + 44 * S
    stats = [("172", "SESSIONS"), ("50", "TILES"), ("3,138", "WORDS"), ("29", "MINUTES")]
    stat_h = 88 * S
    stat_w = (usable_w - 3 * CELL_GAP) / 4
    for i, (num, lab) in enumerate(stats):
        x = content_left + i * (stat_w + CELL_GAP)
        cx, cy = draw_bento_cell(d, x, sy, stat_w, stat_h, lab, pal, compact=True)
        d.text((cx, cy), num, font=font_departure(28 * S), fill=c(pal, "label"))
        # Short neutral tick (not a full-width rule)
        tick_y = cy + 36 * S
        d.rectangle(
            [cx, tick_y, cx + 28 * S, tick_y + 3 * S],
            fill=c(pal, "stat_rule"),
            outline=c(pal, "label"),
            width=1,
        )

    # Row 2: RECENT (~2/3) + THIS WEEK (~1/3)
    r2y = sy + stat_h + BEVEL + CELL_GAP
    week_w = 220 * S
    recent_w = usable_w - week_w - CELL_GAP
    row2_h = 220 * S

    # RECENT cell
    rx, ry = draw_bento_cell(
        d, content_left, r2y, recent_w, row2_h, "RECENT", pal, trailing="All in History →"
    )
    recent = [
        ("11:42", "Ship the folder tabs and keep Start inverted.", "86", True),
        ("Tue", "Dictate standup notes while capturing the board.", "42", True),
        ("Mon", "No speech", "0", False),
        ("Oct 12", "Quick reply about the notarized build.", "19", False),
    ]
    iy = ry
    inner_right = content_left + recent_w - 16 * S
    for when, preview, words, has_thumb in recent:
        d.text((rx, iy + 4 * S), when, font=font_departure(11 * S), fill=c(pal, "secondary"))
        d.text((rx + 52 * S, iy + 4 * S), preview, font=font_departure(11 * S), fill=c(pal, "label"))
        ww, _ = text_size(d, words, font_departure(11 * S))
        thumb_x = inner_right - 28 * S
        d.text((thumb_x - 8 * S - ww, iy + 4 * S), words, font=font_departure(11 * S), fill=c(pal, "secondary"))
        if has_thumb:
            d.rectangle(
                [thumb_x, iy, thumb_x + 28 * S, iy + 28 * S],
                fill=c(pal, "fill"),
                outline=c(pal, "label"),
                width=STROKE,
            )
            d.rectangle(
                [thumb_x + 6 * S, iy + 8 * S, thumb_x + 22 * S, iy + 20 * S],
                outline=c(pal, "secondary"),
                width=STROKE,
            )
        d.rectangle([rx, iy + 34 * S, inner_right, iy + 34 * S + 1], fill=c(pal, "hairline"))
        iy += 40 * S

    # THIS WEEK cell — compact bars (~12pt wide, 6pt gaps)
    wx = content_left + recent_w + CELL_GAP
    week = [12, 40, 8, 90, 55, 20, 70]  # fake words/day; last = today
    week_total = sum(week)
    twx, twy = draw_bento_cell(
        d,
        wx,
        r2y,
        week_w,
        row2_h,
        "THIS WEEK",
        pal,
        trailing=f"{week_total:,} words",
    )
    peak = max(week) or 1
    bar_w = 12 * S
    bar_gap = 6 * S
    bar_max_h = 48 * S
    day_letters = ["F", "S", "S", "M", "T", "W", "T"]
    bar_base = twy + bar_max_h
    for i, (val, letter) in enumerate(zip(week, day_letters)):
        bx = twx + i * (bar_w + bar_gap)
        bh = max(4 * S, (val / peak) * bar_max_h)
        is_today = i == 6
        color = hex_rgb("#ED1C24") if is_today else c(pal, "label")
        # Neutral bars slightly softer; today full red
        if not is_today:
            # approximate 0.75 opacity over front
            fr = c(pal, "front")
            color = tuple(int(a * 0.75 + f * 0.25) for a, f in zip(color, fr))
            if val == 0:
                color = tuple(int(a * 0.22 + f * 0.78) for a, f in zip(c(pal, "label"), fr))
        d.rectangle([bx, bar_base - bh, bx + bar_w, bar_base], fill=color)
        lw, _ = text_size(d, letter, font_departure(11 * S))
        d.text(
            (bx + (bar_w - lw) / 2, bar_base + 4 * S),
            letter,
            font=font_departure(11 * S),
            fill=c(pal, "label" if is_today else "secondary"),
        )
    best = max(week)
    d.text(
        (twx, bar_base + 22 * S),
        f"Best day · {best} words",
        font=font_departure(11 * S),
        fill=c(pal, "secondary"),
    )

    # Row 3: CAPTURE + FOLDER action cells
    r3y = r2y + row2_h + BEVEL + CELL_GAP
    act_w = (usable_w - CELL_GAP) / 2
    act_h = 168 * S
    icon = 40 * S

    # CAPTURE
    cx0, cy0 = draw_bento_cell(d, content_left, r3y, act_w, act_h, "CAPTURE", pal)
    d.rectangle([cx0 + BEVEL, cy0 + BEVEL, cx0 + icon + BEVEL, cy0 + icon + BEVEL], fill=c(pal, "bevel"))
    d.rectangle(
        [cx0, cy0, cx0 + icon, cy0 + icon],
        fill=c(pal, "tile"),
        outline=c(pal, "control"),
        width=STROKE,
    )
    m = 10 * S
    d.rectangle(
        [cx0 + m, cy0 + m, cx0 + icon - m, cy0 + icon - m],
        outline=c(pal, "on_tile"),
        width=STROKE,
    )
    d.text((cx0, cy0 + icon + 8 * S), "Talk, or drag to capture", font=font_departure(13 * S), fill=c(pal, "label"))
    cap_detail = (
        "Hold Shift to mark the screen, then drag. Speech alone pastes the transcript. "
        "A capture pastes the picture with the words."
    )
    ly = cy0 + icon + 28 * S
    for line in wrap(d, cap_detail, font_departure(11 * S), act_w - 36 * S)[:3]:
        d.text((cx0, ly), line, font=font_departure(11 * S), fill=c(pal, "secondary"))
        ly += 14 * S
    # Quiet status caption inside CAPTURE (least clutter)
    d.text(
        (cx0, ly + 6 * S),
        "small.en_217MB · System mic · Permissions OK",
        font=font_departure(11 * S),
        fill=c(pal, "secondary"),
    )

    # FOLDER
    fx = content_left + act_w + CELL_GAP
    fx0, fy0 = draw_bento_cell(d, fx, r3y, act_w, act_h, "FOLDER", pal)
    d.rectangle([fx0 + BEVEL, fy0 + BEVEL, fx0 + icon + BEVEL, fy0 + icon + BEVEL], fill=c(pal, "bevel"))
    d.rectangle(
        [fx0, fy0, fx0 + icon, fy0 + icon],
        fill=c(pal, "tile"),
        outline=c(pal, "control"),
        width=STROKE,
    )
    d.rectangle(
        [fx0 + 12 * S, fy0 + 16 * S, fx0 + icon - 12 * S, fy0 + icon - 10 * S],
        outline=c(pal, "on_tile"),
        width=STROKE,
    )
    d.rectangle(
        [fx0 + 15 * S, fy0 + 10 * S, fx0 + icon - 15 * S, fy0 + 18 * S],
        outline=c(pal, "on_tile"),
        width=STROKE,
    )
    d.text((fx0, fy0 + icon + 8 * S), "Sessions folder", font=font_departure(13 * S), fill=c(pal, "label"))
    d.text(
        (fx0, fy0 + icon + 28 * S),
        "~/Documents/PromptAnnotator/Sessions",
        font=font_departure(11 * S),
        fill=c(pal, "secondary"),
    )
    by = fy0 + icon + 48 * S
    d.rectangle([fx0 + BEVEL, by + BEVEL, fx0 + 48 * S + BEVEL, by + 22 * S + BEVEL], fill=c(pal, "bevel"))
    d.rectangle(
        [fx0, by, fx0 + 48 * S, by + 22 * S],
        fill=c(pal, "front"),
        outline=c(pal, "control"),
        width=STROKE,
    )
    d.text((fx0 + 10 * S, by + 4 * S), "Show", font=font_departure(11 * S), fill=c(pal, "label"))

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
