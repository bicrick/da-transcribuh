#!/usr/bin/env python3
"""Clipboard design A — Maccy structural parity, Paint restyle (light+dark @2×).

Matches Maccy (p0deje/Maccy) layout from SwiftUI sources:
  Popup.window ~450pt, itemHeight 22, horizontal/verticalPadding 5,
  search field ~23pt, imageMaxHeight 40, ⌘1–9 first nine only,
  no row dividers, footer Clear / Preferences… / Quit,
  preview Application / First·Last copy / Number of copies /
  Press ⌥P to (un)pin. / Press ⌥⌫ to delete.

Our language only: Departure Mono, ink palette, square edges, 2pt stroke,
3pt hard offset bevel (black↔#F2F2F2), graphite dark, solid invert selection.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
SYMBOL = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
SYMBOL_SANS = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

S = 2.0  # @2×
# Maccy Popup metrics (pt → px via S)
ITEM_H = int(22 * S)
SEARCH_H = int(23 * S)
H_PAD = int(5 * S)
V_PAD = int(5 * S)
SEP_PAD_H = int(6 * S)
SEP_PAD_V = int(6 * S)
IMG_MAX_H = int(40 * S)
PANEL_W = int(450 * S)
STROKE = int(2 * S)
BEVEL = int(3 * S)

LIGHT = {
    "window": "#FFFFFF",
    "front": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
    "tertiary": "#999999",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "desk": "#5A5A5A",
    "highlight": "#FFF200",
    "sel_bg": "#000000",
    "sel_fg": "#FFFFFF",
    "sel_muted": "#BBBBBB",
    "search_fill": "#F0F0F0",
}
DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "tertiary": "#7A7A80",
    "hairline": "#4A4A4E",
    "bevel": "#F2F2F2",
    "desk": "#1A1A1C",
    "highlight": "#5A5200",
    "sel_bg": "#F2F2F2",
    "sel_fg": "#2C2C2E",
    "sel_muted": "#666666",
    "search_fill": "#353538",
}

# Maccy-lookalike reference chrome (for comparison sheets only)
MACCY_LIGHT = {
    "window": "#F6F6F6",
    "front": "#FFFFFF",
    "fill": "#EBEBEB",
    "label": "#1A1A1A",
    "secondary": "#6E6E73",
    "tertiary": "#8E8E93",
    "hairline": "#D1D1D6",
    "bevel": "#C7C7CC",
    "desk": "#3A3A3C",
    "highlight": "#FFE08A",
    "sel_bg": "#0A84FF",
    "sel_fg": "#FFFFFF",
    "sel_muted": "#D6E9FF",
    "search_fill": "#00000014",
}
MACCY_DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3C",
    "fill": "#48484A",
    "label": "#F5F5F7",
    "secondary": "#98989D",
    "tertiary": "#636366",
    "hairline": "#48484A",
    "bevel": "#1C1C1E",
    "desk": "#000000",
    "highlight": "#5A5200",
    "sel_bg": "#0A84FF",
    "sel_fg": "#FFFFFF",
    "sel_muted": "#B0D0FF",
    "search_fill": "#FFFFFF18",
}

# Mixed history like a busy Maccy session
ROWS = [
    {"kind": "text", "preview": "https://maccy.app — clipboard manager for macOS", "pinned": True},
    {"kind": "text", "preview": "brew install maccy", "pinned": True},
    {"kind": "shot", "preview": "", "thumb": 0},
    {"kind": "text", "preview": "func paste() { simulateCommandV() }", "pinned": False},
    {"kind": "shot", "preview": "", "thumb": 1},
    {"kind": "text", "preview": "okay so the island bevel should invert in dark mode like Maccy keeps the list calm", "pinned": False},
    {"kind": "shot", "preview": "", "thumb": 2},
    {"kind": "text", "preview": "API_BASE=https://api.local/v1", "pinned": False},
    {"kind": "text", "preview": "git push -u origin cursor/clipboard-history-design-b379", "pinned": False},
    {"kind": "shot", "preview": "", "thumb": 0},
    {"kind": "text", "preview": "Press ⌥P to pin. Press ⌥⌫ to delete.", "pinned": False},
    {"kind": "text", "preview": "meeting notes — q3 roadmap draft for da transcribuh", "pinned": False},
    {"kind": "shot", "preview": "", "thumb": 1},
    {"kind": "text", "preview": "NSPasteboard.general.changeCount", "pinned": False},
    {"kind": "text", "preview": "type to search… goes straight into the field — no click", "pinned": False},
]


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def font_symbol(size: float) -> ImageFont.FreeTypeFont:
    path = SYMBOL if SYMBOL.exists() else SYMBOL_SANS
    return ImageFont.truetype(str(path), size=size)


def needs_symbol(ch: str) -> bool:
    return ord(ch) > 127


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    if len(h) == 8:  # AARRGGBB approx → ignore AA
        h = h[2:]
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    v = pal[key]
    if isinstance(v, str) and len(v.lstrip("#")) == 8:
        # treat as RRGGGBB with opacity baked into fill earlier
        return hex_rgb(v)
    return hex_rgb(v) if isinstance(v, str) else v


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def mixed_width(draw: ImageDraw.ImageDraw, text: str, size: float) -> float:
    fd, fs = font(size), font_symbol(size)
    return sum(text_size(draw, ch, fs if needs_symbol(ch) else fd)[0] for ch in text)


def draw_mixed(draw: ImageDraw.ImageDraw, xy: tuple[float, float], text: str, size: float, fill: tuple[int, int, int]) -> float:
    x, y = xy
    fd, fs = font(size), font_symbol(size)
    _, body_h = text_size(draw, "Hg", fd)
    for ch in text:
        f = fs if needs_symbol(ch) else fd
        cw, ch_h = text_size(draw, ch, f)
        draw.text((x, y + (body_h - ch_h) / 2), ch, font=f, fill=fill)
        x += cw
    return x - xy[0]


def mid_truncate(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont, max_w: float) -> str:
    if text_size(draw, text, f)[0] <= max_w:
        return text
    ell = "…"
    left = right = 1
    best = ell
    while left + right < len(text):
        trial = text[:left] + ell + text[-right:]
        if text_size(draw, trial, f)[0] <= max_w:
            best = trial
            if left <= right:
                left += 1
            else:
                right += 1
        else:
            break
    return best


def make_thumb(pal: dict, variant: int, max_h: int = IMG_MAX_H) -> Image.Image:
    """Screenshot-like thumbnail — natural aspect, max height ~Maccy imageMaxHeight."""
    aspects = [1.6, 1.35, 1.8]
    h = max_h
    w = int(h * aspects[variant % 3])
    w = min(w, int(340 * S * 0.55))
    img = Image.new("RGB", (w, h), c(pal, "fill"))
    d = ImageDraw.Draw(img)
    # faux window chrome
    d.rectangle([0, 0, w - 1, h - 1], outline=c(pal, "hairline"))
    d.rectangle([0, 0, w, max(4, h // 5)], fill=c(pal, "window"))
    for i, col in enumerate(["#ED1C24", "#FFCC00", "#22B14C"]):
        d.ellipse([3 + i * 7, 2, 8 + i * 7, 7], fill=hex_rgb(col))
    y0 = h // 5 + 2
    blocks = [
        hex_rgb("#3F48CC"),
        hex_rgb("#FF7F27"),
        hex_rgb("#00A2E8"),
        hex_rgb("#22B14C"),
    ]
    bw = (w - 10) // 3
    for i in range(3):
        d.rectangle([3 + i * (bw + 2), y0, 3 + i * (bw + 2) + bw, h - 3], fill=blocks[(i + variant) % 4])
    return img


def draw_panel_chrome(canvas: Image.Image, ox: int, oy: int, pw: int, ph: int, pal: dict, paint: bool) -> ImageDraw.ImageDraw:
    d = ImageDraw.Draw(canvas)
    if paint:
        d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
        d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "window"), outline=c(pal, "label"), width=STROKE)
    else:
        # Maccy-ish soft panel
        d.rectangle([ox + 4, oy + 6, ox + pw + 4, oy + ph + 6], fill=(0, 0, 0, ))
        d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "window"), outline=c(pal, "hairline"), width=1)
        # soft shadow approximation
        d.rectangle([ox + 2, oy + 3, ox + pw + 2, oy + ph + 3], outline=c(pal, "bevel"))
        d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "window"), outline=c(pal, "hairline"), width=1)
    return d


def draw_header(d: ImageDraw.ImageDraw, ox: int, oy: int, pw: int, pal: dict, query: str, paint: bool, app_name: str) -> int:
    """Maccy ListHeaderView: app name left + search field (23pt)."""
    top = oy + V_PAD
    # Horizontal padding inside list content uses Popup.horizontalPadding via outer; header also +10 in HeaderView
    hx = ox + H_PAD + int(10 * S) if paint else ox + H_PAD + int(10 * S)
    inner_w = pw - 2 * (H_PAD + int(10 * S))

    name_f = font(11 * S)
    nw, nh = text_size(d, app_name, name_f)
    d.text((hx, top + (SEARCH_H - nh) / 2), app_name, font=name_f, fill=c(pal, "secondary"))

    field_x = hx + nw + int(8 * S)
    field_w = hx + inner_w - field_x
    field_y = top
    # Square search (our language) vs slightly rounded feel for Maccy ref (still square pixels but softer fill)
    d.rectangle(
        [field_x, field_y, field_x + field_w, field_y + SEARCH_H],
        fill=c(pal, "search_fill") if paint else c(pal, "fill"),
        outline=c(pal, "label") if paint else c(pal, "hairline"),
        width=STROKE if paint else 1,
    )
    draw_mixed(d, (field_x + int(5 * S), field_y + int(5 * S)), "⌕", 11 * S, c(pal, "secondary"))
    text_x = field_x + int(20 * S)
    if query:
        draw_mixed(d, (text_x, field_y + int(5 * S)), query, 11 * S, c(pal, "label"))
        caret_x = text_x + mixed_width(d, query, 11 * S) + 1
    else:
        draw_mixed(d, (text_x, field_y + int(5 * S)), "type to search…", 11 * S, c(pal, "tertiary"))
        caret_x = text_x
    # focused caret
    _, ch = text_size(d, "Hg", font(11 * S))
    d.rectangle([caret_x, field_y + int(4 * S), caret_x + int(1.5 * S), field_y + int(4 * S) + ch], fill=c(pal, "label"))
    return V_PAD + SEARCH_H + V_PAD


def row_height(row: dict) -> int:
    if row.get("kind") == "shot":
        return max(ITEM_H, IMG_MAX_H + int(10 * S))  # vertical padding 5+5 around image
    return ITEM_H


def draw_rows(
    d: ImageDraw.ImageDraw,
    canvas: Image.Image,
    ox: int,
    y0: int,
    pw: int,
    rows: list[dict],
    pal: dict,
    selected: int,
    query: str = "",
    paint: bool = True,
    max_rows: int | None = None,
) -> float:
    y = float(y0)
    visible = rows if max_rows is None else rows[:max_rows]
    content_x = ox + H_PAD
    content_r = ox + pw - H_PAD

    # Pin separator after last pinned (Maccy PinsView + Divider)
    pinned_count = sum(1 for r in visible if r.get("pinned"))
    for i, row in enumerate(visible):
        rh = row_height(row)
        sel = i == selected
        bg = c(pal, "sel_bg") if sel else c(pal, "window")
        fg = c(pal, "sel_fg") if sel else c(pal, "label")
        muted = c(pal, "sel_muted") if sel else c(pal, "secondary")

        # Full-width highlight with slight inset like Maccy padding (horizontalPadding 5 already on content)
        # Selection bar inset: draw inside content margins
        inset = H_PAD
        d.rectangle([ox + inset, y, ox + pw - inset, y + rh], fill=bg)

        left = content_x + int(10 * S)  # ListItemView spacer width 10 when no app icons
        right = content_r - int(10 * S)

        # ⌘N for first 9 only (right)
        digit = ""
        if i < 9:
            digit = f"⌘{i + 1}"
            dw = mixed_width(d, digit, 10 * S)
            draw_mixed(d, (right - dw, y + (rh - text_size(d, "Hg", font(10 * S))[1]) / 2), digit, 10 * S, muted)
            right -= dw + int(5 * S)

        if row.get("kind") == "shot":
            thumb = make_thumb(pal, int(row.get("thumb", 0)))
            ty = int(y + (rh - thumb.height) / 2)
            canvas.paste(thumb, (int(left), ty))
            # no caption text for image rows (Maccy shows image instead of title)
        else:
            f_body = font(12 * S)
            preview = mid_truncate(d, row["preview"], f_body, right - left)
            if query and query.lower() in preview.lower() and not sel:
                q = query.lower()
                idx = preview.lower().find(q)
                before, match, after = preview[:idx], preview[idx : idx + len(q)], preview[idx + len(q) :]
                bx = left
                th = text_size(d, "Hg", f_body)[1]
                by = y + (rh - th) / 2
                if before:
                    d.text((bx, by), before, font=f_body, fill=fg)
                    bx += text_size(d, before, f_body)[0]
                mw, mh = text_size(d, match, f_body)
                d.rectangle([bx - 1, by - 1, bx + mw + 1, by + mh + 1], fill=c(pal, "highlight"))
                d.text((bx, by), match, font=f_body, fill=c(pal, "label"))
                bx += mw
                if after:
                    d.text((bx, by), after, font=f_body, fill=fg)
            else:
                tw, th = text_size(d, preview, f_body)
                d.text((left, y + (rh - th) / 2), preview, font=f_body, fill=fg)

        y += rh

        # Divider only after pin section (not between rows)
        if pinned_count and i == pinned_count - 1 and i < len(visible) - 1:
            y += SEP_PAD_V
            d.rectangle(
                [ox + SEP_PAD_H, y, ox + pw - SEP_PAD_H, y + 1],
                fill=c(pal, "hairline"),
            )
            y += SEP_PAD_V

    return y


def draw_footer(d: ImageDraw.ImageDraw, ox: int, y: float, pw: int, pal: dict, paint: bool, selected_footer: int = -1) -> float:
    """Maccy footer: divider + Clear / Preferences… / Quit (quiet)."""
    y += SEP_PAD_V
    d.rectangle([ox + SEP_PAD_H, y, ox + pw - SEP_PAD_H, y + 1], fill=c(pal, "hairline"))
    y += SEP_PAD_V

    items = [
        ("Clear", "⌥⌘⌫"),
        ("Preferences…", "⌘,"),
        ("Quit", "⌘Q"),
    ]
    for i, (title, shortcut) in enumerate(items):
        sel = i == selected_footer
        bg = c(pal, "sel_bg") if sel else c(pal, "window")
        fg = c(pal, "sel_fg") if sel else c(pal, "label")
        muted = c(pal, "sel_muted") if sel else c(pal, "secondary")
        d.rectangle([ox + H_PAD, y, ox + pw - H_PAD, y + ITEM_H], fill=bg)
        d.text((ox + H_PAD + int(10 * S), y + (ITEM_H - text_size(d, "Hg", font(12 * S))[1]) / 2), title, font=font(12 * S), fill=fg)
        sw = mixed_width(d, shortcut, 10 * S)
        draw_mixed(
            d,
            (ox + pw - H_PAD - int(10 * S) - sw, y + (ITEM_H - text_size(d, "Hg", font(10 * S))[1]) / 2),
            shortcut,
            10 * S,
            muted,
        )
        y += ITEM_H
    y += V_PAD
    return y


def render_panel(
    pal: dict,
    *,
    paint: bool,
    app_name: str,
    rows: list[dict],
    selected: int,
    query: str = "",
    show_footer: bool = True,
    max_rows: int | None = None,
    caption: str = "",
) -> Image.Image:
    # Measure height
    header_h = V_PAD + SEARCH_H + V_PAD
    list_h = 0.0
    visible = rows if max_rows is None else rows[:max_rows]
    pinned_count = sum(1 for r in visible if r.get("pinned"))
    for i, row in enumerate(visible):
        list_h += row_height(row)
        if pinned_count and i == pinned_count - 1 and i < len(visible) - 1:
            list_h += SEP_PAD_V * 2 + 1
    footer_h = (SEP_PAD_V * 2 + 1 + ITEM_H * 3 + V_PAD) if show_footer else V_PAD
    ph = int(header_h + list_h + footer_h)
    pw = PANEL_W
    margin = 28
    canvas = Image.new("RGB", (pw + (BEVEL if paint else 8) + margin * 2, ph + (BEVEL if paint else 8) + margin * 2 + 40), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_panel_chrome(canvas, ox, oy, pw, ph, pal, paint)
    hh = draw_header(d, ox, oy, pw, pal, query, paint, app_name)
    y = draw_rows(d, canvas, ox, oy + hh, pw, rows, pal, selected, query=query, paint=paint, max_rows=max_rows)
    if show_footer:
        draw_footer(d, ox, y, pw, pal, paint)
    if caption:
        cf = font(11 * S)
        tw, _ = text_size(d, caption, cf)
        d.text(((canvas.width - tw) / 2, canvas.height - 28), caption, font=cf, fill=(190, 190, 190))
    return canvas


def draw_preview_popover(canvas: Image.Image, px: int, py: int, pal: dict, *, mode: str, paint: bool, body: list[str] | None, thumb_v: int, pinned: bool) -> tuple[int, int]:
    pop_w = int(280 * S)
    pad = int(12 * S)
    preview_h = int(160 * S) if mode == "image" else int(120 * S)
    meta_lines = 6
    pop_h = pad + preview_h + int(12 * S) + meta_lines * int(16 * S) + pad
    d = ImageDraw.Draw(canvas)
    if paint:
        d.rectangle([px + BEVEL, py + BEVEL, px + pop_w + BEVEL, py + pop_h + BEVEL], fill=c(pal, "bevel"))
        d.rectangle([px, py, px + pop_w, py + pop_h], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    else:
        d.rectangle([px, py, px + pop_w, py + pop_h], fill=c(pal, "front"), outline=c(pal, "hairline"), width=1)

    ix, iy = px + pad, py + pad
    iw = pop_w - 2 * pad
    if mode == "image":
        big = make_thumb(pal, thumb_v, max_h=preview_h - 4)
        scale = min(iw / big.width, (preview_h - 4) / big.height)
        nw, nh = max(1, int(big.width * scale)), max(1, int(big.height * scale))
        big = big.resize((nw, nh), Image.Resampling.NEAREST)
        bx = ix + (iw - nw) // 2
        by = iy + (preview_h - nh) // 2
        d.rectangle([ix, iy, ix + iw, iy + preview_h], fill=c(pal, "fill"))
        canvas.paste(big, (bx, by))
    else:
        d.rectangle([ix, iy, ix + iw, iy + preview_h], fill=c(pal, "fill"), outline=c(pal, "hairline"))
        f = font(11 * S)
        ty = iy + 8 * S
        for line in body or []:
            words = line.split() or [""]
            cur = ""
            for w in words:
                trial = w if not cur else f"{cur} {w}"
                if text_size(d, trial, f)[0] <= iw - 12 * S:
                    cur = trial
                else:
                    if cur:
                        d.text((ix + 6 * S, ty), cur, font=f, fill=c(pal, "label"))
                        ty += 14 * S
                    cur = w
                    if ty > iy + preview_h - 16 * S:
                        break
            if cur and ty <= iy + preview_h - 16 * S:
                d.text((ix + 6 * S, ty), cur, font=f, fill=c(pal, "label"))
                ty += 14 * S

    my = iy + preview_h + int(10 * S)
    d.rectangle([px + pad, my, px + pop_w - pad, my + 1], fill=c(pal, "hairline"))
    my += int(10 * S)
    meta = [
        ("Application:", "Safari" if mode == "image" else "Cursor"),
        ("First copy time:", "Oct 21, 2026 at 6:02 PM"),
        ("Last copy time:", "Oct 22, 2026 at 11:08 AM"),
        ("Number of copies:", "4" if mode != "image" else "1"),
    ]
    for label, value in meta:
        d.text((px + pad, my), label, font=font(10 * S), fill=c(pal, "tertiary"))
        lw = text_size(d, label, font(10 * S))[0]
        d.text((px + pad + lw + 6 * S, my), value, font=font(10 * S), fill=c(pal, "label"))
        my += int(15 * S)
    pin_line = "Press ⌥P to unpin." if pinned else "Press ⌥P to pin."
    draw_mixed(d, (px + pad, my), pin_line, 10 * S, c(pal, "secondary"))
    my += int(15 * S)
    draw_mixed(d, (px + pad, my), "Press ⌥⌫ to delete.", 10 * S, c(pal, "secondary"))
    return pop_w, pop_h


def render_with_preview(pal: dict, *, paint: bool, app_name: str, mode: str, selected: int, caption: str) -> Image.Image:
    panel = render_panel(pal, paint=paint, app_name=app_name, rows=ROWS, selected=selected, show_footer=True, caption="")
    # Compose with popover to the right
    gap = int(10 * S)
    pop_w, pop_h = int(280 * S), int(340 * S)
    margin = 24
    W = panel.width + gap + pop_w + BEVEL + margin
    H = max(panel.height, pop_h + margin * 2 + 40)
    canvas = Image.new("RGB", (W, H), c(pal, "desk"))
    canvas.paste(panel, (0, 0))
    # Find panel origin of list chrome
    px = panel.width - margin + gap - 8
    # Align near selected row roughly mid
    py = margin + int(80 * S)
    body = None
    thumb_v = 0
    pinned = False
    if mode == "text":
        body = [
            "func paste() {",
            "  simulateCommandV()",
            "}",
            "",
            "// HotkeyChord.canRegister(allowingShift: true)",
        ]
        # select code-ish row index 3
    else:
        thumb_v = 0
    draw_preview_popover(
        canvas, px, py, pal, mode=mode, paint=paint, body=body, thumb_v=thumb_v, pinned=pinned
    )
    d = ImageDraw.Draw(canvas)
    cf = font(11 * S)
    tw, _ = text_size(d, caption, cf)
    d.text(((canvas.width - tw) / 2, canvas.height - 28), caption, font=cf, fill=(190, 190, 190))
    return canvas


def side_by_side(left: Image.Image, right: Image.Image, label_l: str, label_r: str, desk: tuple[int, int, int]) -> Image.Image:
    gap = 28
    label_h = 36
    W = left.width + right.width + gap + 40
    H = max(left.height, right.height) + label_h + 40
    sheet = Image.new("RGB", (W, H), desk)
    d = ImageDraw.Draw(sheet)
    d.text((20, 10), label_l, font=font(12), fill=(220, 220, 220))
    d.text((20 + left.width + gap, 10), label_r, font=font(12), fill=(220, 220, 220))
    sheet.paste(left, (20, label_h))
    sheet.paste(right, (20 + left.width + gap, label_h))
    return sheet


def assert_usable(img: Image.Image, name: str) -> None:
    if img.convert("L").getextrema()[0] == img.convert("L").getextrema()[1]:
        raise SystemExit(f"FAIL {name}: blank")
    tones = sum(1 for v in img.convert("L").histogram() if v > 0)
    if tones < 8:
        raise SystemExit(f"FAIL {name}: few tones")
    print(f"ok {name}: {img.size[0]}x{img.size[1]} tones={tones}")


def save(name: str, img: Image.Image) -> None:
    assert_usable(img, name)
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}-2x.png")
    img.save(OUT_MOCKS / f"{name}.png")
    print("wrote", name)


def main() -> None:
    assert DEPARTURE.exists()
    assert SYMBOL.exists() or SYMBOL_SANS.exists()

    for mode, paint_pal, maccy_pal in (
        ("light", LIGHT, MACCY_LIGHT),
        ("dark", DARK, MACCY_DARK),
    ):
        # Our Paint panels
        ours_default = render_panel(
            paint_pal, paint=True, app_name="da transcribuh", rows=ROWS, selected=3,
            caption="ours · Maccy parity · Paint chrome",
        )
        ours_selected = render_panel(
            paint_pal, paint=True, app_name="da transcribuh", rows=ROWS, selected=2,
            caption="ours · selection invert",
        )
        ours_search = render_panel(
            paint_pal, paint=True, app_name="da transcribuh",
            rows=[r for r in ROWS if "bevel" in r.get("preview", "").lower() or "invert" in r.get("preview", "").lower()]
            or [{"kind": "text", "preview": "okay so the island bevel should invert in dark mode like Maccy keeps the list calm", "pinned": False},
                {"kind": "text", "preview": "Ink.bevel offset 3pt — invert selection", "pinned": False}],
            selected=0, query="bevel",
            caption="ours · search filter",
        )
        ours_prev_img = render_with_preview(
            paint_pal, paint=True, app_name="da transcribuh", mode="image", selected=2,
            caption="ours · preview · image",
        )
        ours_prev_txt = render_with_preview(
            paint_pal, paint=True, app_name="da transcribuh", mode="text", selected=3,
            caption="ours · preview · text",
        )

        # Maccy reference chrome (same structure/content)
        ref_default = render_panel(
            maccy_pal, paint=False, app_name="Maccy", rows=ROWS, selected=3,
            caption="Maccy reference · same structure",
        )
        ref_selected = render_panel(
            maccy_pal, paint=False, app_name="Maccy", rows=ROWS, selected=2,
            caption="Maccy reference · selection",
        )
        ref_search = render_panel(
            maccy_pal, paint=False, app_name="Maccy",
            rows=[r for r in ROWS if "bevel" in r.get("preview", "").lower() or "invert" in r.get("preview", "").lower()]
            or [{"kind": "text", "preview": "okay so the island bevel should invert in dark mode like Maccy keeps the list calm", "pinned": False}],
            selected=0, query="bevel",
            caption="Maccy reference · search",
        )
        ref_prev_img = render_with_preview(
            maccy_pal, paint=False, app_name="Maccy", mode="image", selected=2,
            caption="Maccy reference · preview image",
        )
        ref_prev_txt = render_with_preview(
            maccy_pal, paint=False, app_name="Maccy", mode="text", selected=3,
            caption="Maccy reference · preview text",
        )

        for name, img in {
            f"clipboard-a-default-{mode}": ours_default,
            f"clipboard-a-selected-{mode}": ours_selected,
            f"clipboard-a-search-{mode}": ours_search,
            f"clipboard-a-preview-image-{mode}": ours_prev_img,
            f"clipboard-a-preview-text-{mode}": ours_prev_txt,
            f"clipboard-a-maccy-ref-default-{mode}": ref_default,
            f"clipboard-a-maccy-ref-selected-{mode}": ref_selected,
            f"clipboard-a-maccy-ref-search-{mode}": ref_search,
            f"clipboard-a-maccy-ref-preview-image-{mode}": ref_prev_img,
            f"clipboard-a-maccy-ref-preview-text-{mode}": ref_prev_txt,
        }.items():
            save(name, img)

        desk = c(paint_pal, "desk")
        save(
            f"clipboard-a-compare-default-{mode}",
            side_by_side(ref_default, ours_default, "Maccy structure (ref)", "da transcribuh Paint", desk),
        )
        save(
            f"clipboard-a-compare-selected-{mode}",
            side_by_side(ref_selected, ours_selected, "Maccy selection", "ours invert", desk),
        )
        save(
            f"clipboard-a-compare-search-{mode}",
            side_by_side(ref_search, ours_search, "Maccy search", "ours search", desk),
        )
        save(
            f"clipboard-a-compare-preview-image-{mode}",
            side_by_side(ref_prev_img, ours_prev_img, "Maccy preview", "ours preview", desk),
        )
        save(
            f"clipboard-a-compare-preview-text-{mode}",
            side_by_side(ref_prev_txt, ours_prev_txt, "Maccy preview", "ours preview", desk),
        )

        # Contact sheets
        from functools import reduce

        def sheet(imgs: list[Image.Image], title: str) -> Image.Image:
            gap = 16
            cols = 2
            cw, ch = max(i.width for i in imgs), max(i.height for i in imgs)
            rows = (len(imgs) + cols - 1) // cols
            out = Image.new("RGB", (cols * cw + (cols + 1) * gap, rows * ch + (rows + 1) * gap + 40), desk)
            d = ImageDraw.Draw(out)
            d.text((gap, 12), title, font=font(13), fill=(220, 220, 220))
            for i, im in enumerate(imgs):
                r, cidx = divmod(i, cols)
                out.paste(im, (gap + cidx * (cw + gap), 40 + gap + r * (ch + gap)))
            return out

        save(
            f"clipboard-a-states-{mode}",
            sheet([ours_default, ours_selected, ours_search], f"ours states · {mode}"),
        )
        save(
            f"clipboard-a-preview-{mode}",
            sheet([ours_prev_img, ours_prev_txt], f"ours preview · {mode}"),
        )
        save(
            f"clipboard-a-compare-{mode}",
            sheet(
                [
                    Image.open(OUT / f"clipboard-a-compare-default-{mode}-2x.png"),
                    Image.open(OUT / f"clipboard-a-compare-selected-{mode}-2x.png"),
                    Image.open(OUT / f"clipboard-a-compare-search-{mode}-2x.png"),
                    Image.open(OUT / f"clipboard-a-compare-preview-image-{mode}-2x.png"),
                ],
                f"Maccy vs ours · {mode}",
            ),
        )

    print("done")


if __name__ == "__main__":
    main()
