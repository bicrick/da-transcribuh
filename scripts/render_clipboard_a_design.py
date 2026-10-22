#!/usr/bin/env python3
"""Direction A clipboard mocks — refined Maccy-like compact list (light+dark @2×).

Header: app label + focused search (caret, “type to search…”, magnifier).
Rows: no type boxes; mid-truncated text; ~48pt image thumbs; ⌘N right, muted;
      pin mark; selected = solid invert. Footer: short muted hints (DejaVu glyphs).
Chrome: Departure Mono UI, 2pt stroke, 3pt hard offset bevel.
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

S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)
ROW_H_TEXT = int(36 * S)
ROW_H_IMG = int(56 * S)
THUMB_H = int(48 * S)
PAD = int(12 * S)

LIGHT = {
    "window": "#FFFFFF",
    "front": "#FFFFFF",
    "fill": "#F0F0F0",
    "card": "#FFFFFF",
    "label": "#000000",
    "secondary": "#666666",
    "tertiary": "#999999",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "desk": "#5A5A5A",
    "highlight": "#FFF200",
    "sel_bg": "#000000",
    "sel_fg": "#FFFFFF",
    "sel_muted": "#AAAAAA",
}
DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "card": "#353538",
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
}

FOOTER = "↑↓  ↩ paste  ⌥↩ copy  ⌘1–9  ⌥P pin  Esc"

DEFAULT_ROWS = [
    {"kind": "text", "preview": "API_BASE=https://api.local/v1", "tag": "", "pinned": True},
    {"kind": "code", "preview": "func paste() { simulateCommandV() }", "tag": "", "pinned": False},
    {"kind": "url", "preview": "https://github.com/bicrick/da-transcribuh", "tag": "", "pinned": False},
    {"kind": "transcript", "preview": "okay so the island bevel should invert in dark mode", "tag": "words", "pinned": False},
    {"kind": "shot", "preview": "Home bento", "tag": "tile", "pinned": False, "thumb": 0},
    {"kind": "text", "preview": "meeting notes — q3 roadmap draft", "tag": "", "pinned": False},
    {"kind": "transcript", "preview": "ship the compact clipboard panel first", "tag": "words", "pinned": False},
]

LONG_ROWS = [
    {"kind": k, "preview": p, "tag": t, "pinned": pin, **({"thumb": i % 3} if k == "shot" else {})}
    for i, (k, p, t, pin) in enumerate(
        [
            ("text", "API_BASE=https://api.local/v1", "", True),
            ("code", "guard chord.canRegister(allowingShift: true)", "", False),
            ("url", "https://docs.example.com/clipboard", "", False),
            ("transcript", "type straight into search, no click needed", "words", False),
            ("shot", "Appearance graphite", "tile", False),
            ("text", "patrick@da-transcribuh design review", "", False),
            ("code", "RegisterEventHotKey(/* id 4 */)", "", False),
            ("transcript", "Esc clears search then closes the panel", "words", False),
            ("shot", "recording island", "tile", False),
            ("text", "Maccy-like: ⌃N ⌃P move selection", "", False),
            ("url", "https://github.com/p0deje/Maccy", "", False),
            ("text", "pinned items stay above recents", "", False),
            ("transcript", "paste back uses Accessibility we already have", "words", False),
            ("shot", "Models picker", "tile", False),
            ("code", "NSPasteboard.general.changeCount", "", False),
        ]
    )
]


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def font_symbol(size: float) -> ImageFont.FreeTypeFont:
    path = SYMBOL if SYMBOL.exists() else SYMBOL_SANS
    return ImageFont.truetype(str(path), size=size) if path.exists() else font(size)


def needs_symbol(ch: str) -> bool:
    return ord(ch) > 127


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def mixed_width(draw: ImageDraw.ImageDraw, text: str, size: float) -> float:
    fd, fs = font(size), font_symbol(size)
    return sum(text_size(draw, ch, fs if needs_symbol(ch) else fd)[0] for ch in text)


def draw_mixed(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    size: float,
    fill: tuple[int, int, int],
) -> float:
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
    if text_size(draw, ell, f)[0] >= max_w:
        return ell
    left, right = 1, 1
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


def keycap_font(label: str, h: float) -> ImageFont.FreeTypeFont:
    if any(needs_symbol(ch) for ch in label):
        return font_symbol(h * 0.42)
    return font(h * 0.38 if len(label) > 1 else h * 0.42)


def keycap_width(draw: ImageDraw.ImageDraw, label: str, h: float = 26 * S) -> float:
    tw, _ = text_size(draw, label, keycap_font(label, h))
    pad = 12 * S if len(label) > 2 else (10 * S if len(label) > 1 else 8 * S)
    return max(h, tw + pad * 2)


def draw_keycap(draw: ImageDraw.ImageDraw, x: float, y: float, label: str, pal: dict, h: float = 26 * S) -> float:
    f = keycap_font(label, h)
    tw, th = text_size(draw, label, f)
    w = keycap_width(draw, label, h)
    draw.rectangle([x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), label, font=f, fill=c(pal, "label"))
    return w


def draw_bevel_panel(canvas: Image.Image, ox: int, oy: int, pw: int, ph: int, pal: dict) -> ImageDraw.ImageDraw:
    d = ImageDraw.Draw(canvas)
    d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    return d


def make_thumb(pal: dict, variant: int, h: int = THUMB_H) -> Image.Image:
    """Synthetic but real-looking UI screenshot thumbnail."""
    aspect = 1.55
    w = int(h * aspect)
    img = Image.new("RGB", (w, h), c(pal, "fill"))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], outline=c(pal, "hairline"))
    # title strip
    d.rectangle([0, 0, w, int(h * 0.18)], fill=c(pal, "window"))
    d.rectangle([0, int(h * 0.18), w, int(h * 0.18) + 1], fill=c(pal, "label"))
    accents = ["#ED1C24", "#FF7F27", "#22B14C", "#3F48CC"]
    for i, col in enumerate(accents[:3]):
        d.rectangle([4 + i * 8, 4, 10 + i * 8, 10], fill=hex_rgb(col))
    # content blocks
    palette = [
        hex_rgb("#3F48CC" if variant % 3 == 0 else "#22B14C"),
        hex_rgb("#FF7F27"),
        hex_rgb("#00A2E8"),
    ]
    y0 = int(h * 0.28)
    gap = 4
    cell_w = (w - 16 - gap * 2) // 3
    for i in range(3):
        x = 8 + i * (cell_w + gap)
        d.rectangle([x, y0, x + cell_w, y0 + int(h * 0.32)], fill=palette[(i + variant) % 3])
        d.rectangle([x, y0, x + cell_w, y0 + int(h * 0.32)], outline=c(pal, "label"))
    d.rectangle([8, y0 + int(h * 0.4), w - 8, h - 6], fill=c(pal, "front"), outline=c(pal, "hairline"))
    d.text((12, y0 + int(h * 0.48)), ["Home", "Island", "Models"][variant % 3], font=font(7 * S), fill=c(pal, "label"))
    return img


def draw_pin(d: ImageDraw.ImageDraw, x: float, y: float, pal: dict, fg: tuple[int, int, int]) -> None:
    """Small pin glyph (not a red dot) — simple filled chevron/pin shape."""
    # stem + head as simple geometry
    d.polygon(
        [
            (x + 3 * S, y),
            (x + 7 * S, y),
            (x + 7 * S, y + 6 * S),
            (x + 5 * S, y + 9 * S),
            (x + 3 * S, y + 6 * S),
        ],
        fill=fg,
    )
    d.ellipse([x + 2 * S, y - 1 * S, x + 8 * S, y + 5 * S], outline=fg)


def draw_header(d: ImageDraw.ImageDraw, ox: int, oy: int, pw: int, pal: dict, query: str, focused: bool = True) -> int:
    """App label + search field (focused caret). Returns header height."""
    hh = int(40 * S)
    d.rectangle([ox, oy, ox + pw, oy + hh], fill=c(pal, "front"))
    d.rectangle([ox, oy + hh - STROKE, ox + pw, oy + hh], fill=c(pal, "label"))

    label = "clipboard"
    lf = font(10 * S)
    lw, lh = text_size(d, label, lf)
    d.text((ox + PAD, oy + (hh - lh) / 2 - 1), label, font=lf, fill=c(pal, "tertiary"))

    # Search field to the right of label
    field_x = ox + PAD + lw + int(10 * S)
    field_y = oy + int(8 * S)
    field_h = hh - int(16 * S)
    field_w = ox + pw - PAD - field_x
    d.rectangle(
        [field_x, field_y, field_x + field_w, field_y + field_h],
        fill=c(pal, "fill"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    # Magnifier (simple circle + handle via DejaVu ⌕ or geometry)
    mag = "⌕"
    draw_mixed(d, (field_x + 8 * S, field_y + 5 * S), mag, 11 * S, c(pal, "secondary"))
    text_x = field_x + 24 * S
    if query:
        draw_mixed(d, (text_x, field_y + 5 * S), query, 11 * S, c(pal, "label"))
        caret_x = text_x + mixed_width(d, query, 11 * S) + 2
    else:
        draw_mixed(d, (text_x, field_y + 5 * S), "type to search…", 11 * S, c(pal, "tertiary"))
        caret_x = text_x
    if focused:
        _, ch = text_size(d, "Hg", font(11 * S))
        d.rectangle([caret_x, field_y + 5 * S, caret_x + 2 * S, field_y + 5 * S + ch], fill=c(pal, "label"))
    return hh


def draw_footer(d: ImageDraw.ImageDraw, ox: int, oy: int, pw: int, ph: int, pal: dict) -> None:
    fh = int(24 * S)
    fy = oy + ph - fh
    d.rectangle([ox, fy, ox + pw, oy + ph], fill=c(pal, "fill"))
    d.rectangle([ox, fy, ox + pw, fy + 1], fill=c(pal, "hairline"))
    draw_mixed(d, (ox + PAD, fy + 6 * S), FOOTER, 9 * S, c(pal, "tertiary"))


def row_height(row: dict) -> int:
    return ROW_H_IMG if row.get("kind") == "shot" else ROW_H_TEXT


def draw_rows(
    d: ImageDraw.ImageDraw,
    canvas: Image.Image,
    ox: int,
    list_top: int,
    pw: int,
    rows: list[dict],
    pal: dict,
    selected: int,
    query: str = "",
    max_count: int | None = None,
    fade_bottom: bool = False,
) -> float:
    visible = rows if max_count is None else rows[:max_count]
    y = float(list_top)
    f_body = font(12 * S)
    f_tag = font(9 * S)

    for i, row in enumerate(visible):
        rh = row_height(row)
        selected_row = i == selected
        bg = c(pal, "sel_bg") if selected_row else c(pal, "front")
        fg = c(pal, "sel_fg") if selected_row else c(pal, "label")
        muted = c(pal, "sel_muted") if selected_row else c(pal, "tertiary")
        d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + rh], fill=bg)

        left = ox + PAD
        # Pin mark
        if row.get("pinned"):
            draw_pin(d, left, y + rh / 2 - 4 * S, pal, fg)
            left += 14 * S

        # Image thumbnail or text
        content_right = ox + pw - PAD
        digit = f"⌘{i + 1}" if i < 9 else ""
        digit_w = mixed_width(d, digit, 10 * S) if digit else 0
        if digit:
            content_right -= digit_w + 8 * S

        tag = row.get("tag") or ""
        # Only transcripts get a tiny muted source tag
        show_tag = row.get("kind") == "transcript" and tag
        tag_w = text_size(d, tag, f_tag)[0] + 8 * S if show_tag else 0
        if show_tag:
            content_right -= tag_w

        if row.get("kind") == "shot":
            thumb = make_thumb(pal, int(row.get("thumb", 0)))
            ty = int(y + (rh - thumb.height) / 2)
            canvas.paste(thumb, (int(left), ty))
            # outline thumb
            ImageDraw.Draw(canvas).rectangle(
                [left, ty, left + thumb.width, ty + thumb.height],
                outline=fg if selected_row else c(pal, "hairline"),
            )
            tx = left + thumb.width + 10 * S
            preview = mid_truncate(d, row["preview"], f_body, content_right - tx)
            tw, th = text_size(d, preview, f_body)
            d.text((tx, y + (rh - th) / 2), preview, font=f_body, fill=fg)
        else:
            preview = mid_truncate(d, row["preview"], f_body, content_right - left)
            if query and query.lower() in preview.lower():
                # highlight match span on non-selected rows
                q = query.lower()
                lower = preview.lower()
                idx = lower.find(q)
                if idx >= 0 and not selected_row:
                    before, match, after = preview[:idx], preview[idx : idx + len(q)], preview[idx + len(q) :]
                    bx = left
                    if before:
                        d.text((bx, y + (rh - text_size(d, before, f_body)[1]) / 2), before, font=f_body, fill=fg)
                        bx += text_size(d, before, f_body)[0]
                    mw, mh = text_size(d, match, f_body)
                    by = y + (rh - mh) / 2
                    d.rectangle([bx - 1, by - 1, bx + mw + 1, by + mh + 1], fill=c(pal, "highlight"))
                    d.text((bx, by), match, font=f_body, fill=c(pal, "label"))
                    bx += mw
                    if after:
                        d.text((bx, by), after, font=f_body, fill=fg)
                else:
                    tw, th = text_size(d, preview, f_body)
                    d.text((left, y + (rh - th) / 2), preview, font=f_body, fill=fg)
            else:
                tw, th = text_size(d, preview, f_body)
                d.text((left, y + (rh - th) / 2), preview, font=f_body, fill=fg)

        if show_tag:
            tw, th = text_size(d, tag, f_tag)
            d.text((ox + pw - PAD - digit_w - (8 * S if digit else 0) - tw, y + (rh - th) / 2), tag, font=f_tag, fill=muted)

        if digit:
            draw_mixed(d, (ox + pw - PAD - digit_w, y + (rh - text_size(d, "Hg", font(10 * S))[1]) / 2), digit, 10 * S, muted)

        y += rh
        if not selected_row:
            d.rectangle([ox + PAD, y - 1, ox + pw - PAD, y], fill=c(pal, "hairline"))

    if fade_bottom:
        # scroll cue
        tip = y
        d.rectangle([ox + STROKE, tip, ox + pw - STROKE, tip + 18 * S], fill=c(pal, "front"))
        d.text((ox + PAD, tip + 2 * S), "…", font=font(12 * S), fill=c(pal, "tertiary"))
        track_x = ox + pw - 8 * S
        d.rectangle([track_x, list_top + 4, track_x + 4 * S, tip - 4], fill=c(pal, "fill"))
        d.rectangle([track_x, list_top + 4, track_x + 4 * S, list_top + 60 * S], fill=c(pal, "label"))
    return y


def panel_canvas(pal: dict, ph: float = 440) -> tuple[Image.Image, ImageDraw.ImageDraw, int, int, int, int]:
    pw = int(380 * S)
    height = int(ph * S)
    margin = 28
    canvas = Image.new("RGB", (pw + BEVEL + margin * 2, height + BEVEL + margin * 2 + 36), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, pw, height, pal)
    return canvas, d, ox, oy, pw, height


def caption(canvas: Image.Image, text: str) -> None:
    d = ImageDraw.Draw(canvas)
    f = font(11 * S)
    tw, _ = text_size(d, text, f)
    d.text(((canvas.width - tw) / 2, canvas.height - 28), text, font=f, fill=(190, 190, 190))


def render_default(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal)
    hh = draw_header(d, ox, oy, pw, pal, "", focused=True)
    draw_rows(d, canvas, ox, oy + hh, pw, DEFAULT_ROWS, pal, selected=1)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, "A · refined · search focused · invert select")
    return canvas


def render_selected(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal)
    hh = draw_header(d, ox, oy, pw, pal, "", focused=True)
    draw_rows(d, canvas, ox, oy + hh, pw, DEFAULT_ROWS, pal, selected=3)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, "A · selected · solid invert")
    return canvas


def render_search(pal: dict) -> Image.Image:
    query = "bevel"
    filtered = [r for r in DEFAULT_ROWS + LONG_ROWS if query.lower() in r["preview"].lower()]
    if len(filtered) < 2:
        filtered = [
            {"kind": "transcript", "preview": "okay so the island bevel should invert in dark mode", "tag": "words", "pinned": False},
            {"kind": "text", "preview": "Ink.bevel offset 3pt hard shadow", "tag": "", "pinned": False},
        ]
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=340)
    hh = draw_header(d, ox, oy, pw, pal, query, focused=True)
    draw_rows(d, canvas, ox, oy + hh, pw, filtered, pal, selected=0, query=query)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, "A · type to search · match highlight")
    return canvas


def render_empty(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=280)
    hh = draw_header(d, ox, oy, pw, pal, "", focused=True)
    body_top = oy + hh
    body_bot = oy + ph - int(24 * S)
    mid = (body_top + body_bot) / 2
    msg, sub = "No clipboard items yet", "Copy text or finish a session."
    mw, _ = text_size(d, msg, font(13 * S))
    sw, _ = text_size(d, sub, font(11 * S))
    d.text((ox + (pw - mw) / 2, mid - 16 * S), msg, font=font(13 * S), fill=c(pal, "secondary"))
    d.text((ox + (pw - sw) / 2, mid + 8 * S), sub, font=font(11 * S), fill=c(pal, "tertiary"))
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, "A · empty")
    return canvas


def render_scroll(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=460)
    hh = draw_header(d, ox, oy, pw, pal, "", focused=True)
    draw_rows(d, canvas, ox, oy + hh, pw, LONG_ROWS, pal, selected=2, max_count=7, fade_bottom=True)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, "A · long list · scroll")
    return canvas


def draw_preview_popover(
    canvas: Image.Image,
    px: int,
    py: int,
    pal: dict,
    *,
    mode: str,
    body_lines: list[str] | None = None,
    thumb_variant: int = 0,
    source: str,
    first: str,
    last: str,
    copies: str,
) -> tuple[int, int]:
    pop_w = int(300 * S)
    pad = int(14 * S)
    meta_h = int(100 * S)
    preview_h = int(170 * S) if mode == "image" else int(130 * S)
    pop_h = pad + preview_h + int(10 * S) + meta_h + pad
    d = ImageDraw.Draw(canvas)
    d.rectangle([px + BEVEL, py + BEVEL, px + pop_w + BEVEL, py + pop_h + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([px, py, px + pop_w, py + pop_h], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)

    ix, iy = px + pad, py + pad
    iw, ih = pop_w - 2 * pad, preview_h
    if mode == "image":
        # Large screenshot preview
        big = make_thumb(pal, thumb_variant, h=ih - 4)
        # scale width to fit
        scale = min(iw / big.width, ih / big.height)
        nw, nh = int(big.width * scale), int(big.height * scale)
        big = big.resize((nw, nh), Image.Resampling.NEAREST)
        bx = ix + (iw - nw) // 2
        by = iy + (ih - nh) // 2
        d.rectangle([ix, iy, ix + iw, iy + ih], fill=c(pal, "fill"))
        canvas.paste(big, (bx, by))
        d.rectangle([bx, by, bx + nw, by + nh], outline=c(pal, "label"))
    else:
        d.rectangle([ix, iy, ix + iw, iy + ih], fill=c(pal, "fill"), outline=c(pal, "hairline"))
        f = font(11 * S)
        ty = iy + 10 * S
        for line in body_lines or []:
            # wrap
            words = line.split() or [""]
            cur = ""
            for w in words:
                trial = w if not cur else f"{cur} {w}"
                if text_size(d, trial, f)[0] <= iw - 16 * S:
                    cur = trial
                else:
                    if ty + 14 * S > iy + ih - 8 * S:
                        d.text((ix + 8 * S, ty), "…", font=f, fill=c(pal, "tertiary"))
                        break
                    d.text((ix + 8 * S, ty), cur, font=f, fill=c(pal, "label"))
                    ty += 15 * S
                    cur = w
            else:
                if cur:
                    if ty + 14 * S > iy + ih - 8 * S:
                        d.text((ix + 8 * S, ty), "…", font=f, fill=c(pal, "tertiary"))
                        break
                    d.text((ix + 8 * S, ty), cur, font=f, fill=c(pal, "label"))
                    ty += 15 * S
                    continue
            break

    my = iy + preview_h + int(10 * S)
    d.rectangle([px + STROKE, my, px + pop_w - STROKE, my + 1], fill=c(pal, "hairline"))
    my += 10 * S
    for label, value in [
        ("Source", source),
        ("First copy", first),
        ("Last copy", last),
        ("Copies", copies),
    ]:
        d.text((px + pad, my), label, font=font(10 * S), fill=c(pal, "tertiary"))
        draw_mixed(d, (px + pad + 88 * S, my), value, 10 * S, c(pal, "label"))
        my += 16 * S
    draw_mixed(d, (px + pad, my + 2 * S), "⌥P pin/unpin · ⌥⌫ delete", 9 * S, c(pal, "secondary"))
    return pop_w, pop_h


def render_preview_image(pal: dict) -> Image.Image:
    list_pw, list_ph = int(380 * S), int(440 * S)
    margin, gap = 24, int(10 * S)
    pop_w, pop_h = int(300 * S), int(320 * S)
    W = margin * 2 + list_pw + BEVEL + gap + pop_w + BEVEL
    H = margin * 2 + max(list_ph + BEVEL, pop_h + BEVEL) + 40
    canvas = Image.new("RGB", (W, H), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, list_pw, list_ph, pal)
    hh = draw_header(d, ox, oy, list_pw, pal, "", focused=True)
    draw_rows(d, canvas, ox, oy + hh, list_pw, DEFAULT_ROWS, pal, selected=4)
    draw_footer(d, ox, oy, list_pw, list_ph, pal)
    # estimate row y for shot
    y = oy + hh
    for i, row in enumerate(DEFAULT_ROWS):
        if i == 4:
            break
        y += row_height(row)
    px = ox + list_pw + BEVEL + gap
    py = max(margin, min(int(y - 20 * S), H - margin - pop_h - 40))
    draw_preview_popover(
        canvas, px, py, pal, mode="image", thumb_variant=0,
        source="da transcribuh · screenshot", first="Today 2:14 PM", last="Today 2:14 PM", copies="1",
    )
    caption(canvas, "A · preview · image · ~400ms")
    return canvas


def render_preview_text(pal: dict) -> Image.Image:
    list_pw, list_ph = int(380 * S), int(440 * S)
    margin, gap = 24, int(10 * S)
    pop_w, pop_h = int(300 * S), int(300 * S)
    W = margin * 2 + list_pw + BEVEL + gap + pop_w + BEVEL
    H = margin * 2 + max(list_ph + BEVEL, pop_h + BEVEL) + 40
    canvas = Image.new("RGB", (W, H), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, list_pw, list_ph, pal)
    hh = draw_header(d, ox, oy, list_pw, pal, "", focused=True)
    draw_rows(d, canvas, ox, oy + hh, list_pw, DEFAULT_ROWS, pal, selected=1)
    draw_footer(d, ox, oy, list_pw, list_ph, pal)
    y = oy + hh + row_height(DEFAULT_ROWS[0])
    px = ox + list_pw + BEVEL + gap
    py = max(margin, min(int(y - 10 * S), H - margin - pop_h - 40))
    draw_preview_popover(
        canvas, px, py, pal, mode="text",
        body_lines=[
            "func paste() {",
            "  simulateCommandV()",
            "}",
            "",
            "// HotkeyChord.canRegister(allowingShift: true)",
            "// ⌘⇧C opens history beside the cursor",
        ],
        source="Cursor", first="Yesterday 6:02 PM", last="Today 11:08 AM", copies="4",
    )
    caption(canvas, "A · preview · text/code")
    return canvas


def render_settings(pal: dict) -> Image.Image:
    w, h = int(520 * S), int(420 * S)
    img = Image.new("RGB", (w + 40, h + 60), c(pal, "desk"))
    d = ImageDraw.Draw(img)
    ox, oy = 20, 20
    d.rectangle([ox, oy, ox + w, oy + h], fill=c(pal, "window"))
    d.text((ox + 24 * S, oy + 20 * S), "General", font=font(18 * S), fill=c(pal, "label"))
    d.text((ox + 24 * S, oy + 48 * S), "Shortcuts, launch behavior, and paste rules.", font=font(11 * S), fill=c(pal, "secondary"))
    cx, cy = ox + 24 * S, oy + 80 * S
    cw, ch = w - 48 * S, int(280 * S)
    d.rectangle([cx + BEVEL, cy + BEVEL, cx + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([cx, cy, cx + cw, cy + ch], fill=c(pal, "card"), outline=c(pal, "label"), width=STROKE)
    d.text((cx + 16 * S, cy + 14 * S), "Clipboard", font=font(13 * S), fill=c(pal, "label"))
    draw_mixed(d, (cx + 16 * S, cy + 36 * S), "Maccy-style history. Uses Accessibility (already needed for paste).", 10 * S, c(pal, "secondary"))

    ry = cy + 64 * S
    d.rectangle([cx + STROKE, ry, cx + cw - STROKE, ry + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry + 14 * S), "Enable clipboard history", font=font(12 * S), fill=c(pal, "label"))
    draw_mixed(d, (cx + 16 * S, ry + 34 * S), "On by default. ⌘⇧C opens the panel near the pointer.", 10 * S, c(pal, "secondary"))
    tx = cx + cw - 52 * S
    d.rectangle([tx, ry + 18 * S, tx + 36 * S, ry + 36 * S], fill=c(pal, "label"), outline=c(pal, "label"), width=STROKE)
    d.rectangle([tx + 18 * S, ry + 20 * S, tx + 34 * S, ry + 34 * S], fill=c(pal, "front"))

    ry2 = ry + 60 * S
    d.rectangle([cx + STROKE, ry2, cx + cw - STROKE, ry2 + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry2 + 14 * S), "Shortcut", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + 16 * S, ry2 + 34 * S), "click to rebind", font=font(10 * S), fill=c(pal, "secondary"))
    caps = ["⌘", "⇧", "C"]
    widths = [keycap_width(d, cap, 24 * S) for cap in caps]
    kx = cx + cw - 16 * S - (sum(widths) + 6 * S * (len(caps) - 1))
    for cap, ww in zip(caps, widths):
        draw_keycap(d, kx, ry2 + 14 * S, cap, pal, h=24 * S)
        kx += ww + 6 * S

    ry3 = ry2 + 64 * S
    d.rectangle([cx + STROKE, ry3, cx + cw - STROKE, ry3 + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry3 + 14 * S), "History limit", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + cw - 48 * S, ry3 + 14 * S), "200", font=font(12 * S), fill=c(pal, "label"))

    ry4 = ry3 + 48 * S
    d.rectangle([cx + STROKE, ry4, cx + cw - STROKE, ry4 + 1], fill=c(pal, "hairline"))
    draw_mixed(d, (cx + 16 * S, ry4 + 16 * S), "Reset to ⌘⇧C", 11 * S, c(pal, "secondary"))
    d.text((cx + 160 * S, ry4 + 16 * S), "Clear history", font=font(11 * S), fill=c(pal, "secondary"))
    assert ry4 + 40 * S < cy + ch

    caption(img, "settings · General · Clipboard")
    return img


def render_onboarding_keybinds(pal: dict) -> Image.Image:
    w, h = int(560 * S), int(500 * S)
    img = Image.new("RGB", (w, h), c(pal, "window"))
    d = ImageDraw.Draw(img)
    tw, th = text_size(d, "da transcribuh", font(13 * S))
    d.text(((w - tw) / 2, (40 * S - th) / 2), "da transcribuh", font=font(13 * S), fill=c(pal, "label"))
    d.rectangle([0, 40 * S - STROKE, w, 40 * S], fill=c(pal, "label"))

    labels = ["Hi", "Perm", "Keys", "Clip", "Look", "Model", "Try", "Go"]
    x = 36 * S
    for i, lab in enumerate(labels):
        col = c(pal, "label") if i == 2 else c(pal, "secondary")
        d.text((x, 56 * S), lab, font=font(10 * S), fill=col)
        lw, _ = text_size(d, lab, font(10 * S))
        if i == 2:
            d.rectangle([x, 56 * S + 16 * S, x + lw, 56 * S + 16 * S + STROKE], fill=c(pal, "label"))
        x += lw + 14 * S

    d.text((36 * S, 90 * S), "Keybinds", font=font(18 * S), fill=c(pal, "label"))
    draw_mixed(d, (36 * S, 122 * S), "Recording defaults to ⌥Space. Clipboard history uses ⌘⇧C.", 12 * S, c(pal, "secondary"))
    draw_mixed(d, (36 * S, 146 * S), "⌘Space and ⌥⌘Space stay with the system.", 12 * S, c(pal, "secondary"))

    def chord_card(cy: float, title: str, hint: str, caps: list[str]) -> None:
        cw = w - 72 * S
        ch = 96 * S
        d.rectangle([36 * S + BEVEL, cy + BEVEL, 36 * S + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
        d.rectangle([36 * S, cy, 36 * S + cw, cy + ch], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
        d.text((36 * S + 16 * S, cy + 14 * S), title, font=font(12 * S), fill=c(pal, "label"))
        d.text((36 * S + 16 * S, cy + 38 * S), hint, font=font(10 * S), fill=c(pal, "secondary"))
        widths = [keycap_width(d, cap, 26 * S) for cap in caps]
        kx = 36 * S + cw - 16 * S - (sum(widths) + 6 * S * (len(caps) - 1))
        for cap, ww in zip(caps, widths):
            draw_keycap(d, kx, cy + 32 * S, cap, pal, h=26 * S)
            kx += ww + 6 * S
        d.text((36 * S + 16 * S, cy + 70 * S), "Change", font=font(11 * S), fill=c(pal, "secondary"))

    chord_card(180 * S, "Recording", "click to rebind", ["⌥", "Space"])
    chord_card(300 * S, "Clipboard history", "click to rebind", ["⌘", "⇧", "C"])

    d.rectangle([0, h - 56 * S, w, h], fill=c(pal, "window"))
    d.rectangle([0, h - 56 * S, w, h - 56 * S + 1], fill=c(pal, "hairline"))
    d.text((36 * S, h - 36 * S), "3 / 8", font=font(11 * S), fill=c(pal, "secondary"))
    d.rectangle([w - 140 * S, h - 44 * S, w - 36 * S, h - 16 * S], fill=c(pal, "label"))
    d.text((w - 118 * S, h - 36 * S), "Continue", font=font(12 * S), fill=c(pal, "window"))
    return img


def render_onboarding_clipboard(pal: dict) -> Image.Image:
    w, h = int(560 * S), int(500 * S)
    img = Image.new("RGB", (w, h), c(pal, "window"))
    d = ImageDraw.Draw(img)
    tw, th = text_size(d, "da transcribuh", font(13 * S))
    d.text(((w - tw) / 2, (40 * S - th) / 2), "da transcribuh", font=font(13 * S), fill=c(pal, "label"))
    d.rectangle([0, 40 * S - STROKE, w, 40 * S], fill=c(pal, "label"))

    labels = ["Hi", "Perm", "Keys", "Clip", "Look", "Model", "Try", "Go"]
    x = 36 * S
    for i, lab in enumerate(labels):
        col = c(pal, "label") if i == 3 else c(pal, "secondary")
        d.text((x, 56 * S), lab, font=font(10 * S), fill=col)
        lw, _ = text_size(d, lab, font(10 * S))
        if i == 3:
            d.rectangle([x, 56 * S + 16 * S, x + lw, 56 * S + 16 * S + STROKE], fill=c(pal, "label"))
        x += lw + 14 * S

    d.text((36 * S, 90 * S), "Clipboard history", font=font(18 * S), fill=c(pal, "label"))
    for i, line in enumerate([
        "Compact list at the cursor. Type to search, Enter pastes.",
        "Copies, transcripts, and screenshots land here.",
        "Accessibility for paste already covers this — nothing new to grant.",
    ]):
        d.text((36 * S, 122 * S + i * 22 * S), line, font=font(12 * S), fill=c(pal, "secondary"))

    cy = 200 * S
    cw = w - 72 * S
    ch = 190 * S
    d.rectangle([36 * S + BEVEL, cy + BEVEL, 36 * S + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([36 * S, cy, 36 * S + cw, cy + ch], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    d.text((36 * S + 16 * S, cy + 16 * S), "Enable clipboard history", font=font(12 * S), fill=c(pal, "label"))
    d.text((36 * S + 16 * S, cy + 38 * S), "On by default. Off anytime in General.", font=font(10 * S), fill=c(pal, "secondary"))
    tx = 36 * S + cw - 52 * S
    d.rectangle([tx, cy + 20 * S, tx + 36 * S, cy + 38 * S], fill=c(pal, "label"), outline=c(pal, "label"), width=STROKE)
    d.rectangle([tx + 18 * S, cy + 22 * S, tx + 34 * S, cy + 36 * S], fill=c(pal, "front"))

    d.rectangle([36 * S, cy + 56 * S, 36 * S + cw, cy + 56 * S + 1], fill=c(pal, "hairline"))
    d.text((36 * S + 16 * S, cy + 70 * S), "Keyboard", font=font(11 * S), fill=c(pal, "label"))
    draw_mixed(d, (36 * S + 16 * S, cy + 94 * S), "Type → filter   ↑↓ → move   ↩ → paste   Esc → clear / close", 10 * S, c(pal, "secondary"))
    draw_mixed(d, (36 * S + 16 * S, cy + 118 * S), "⌘1–9 instant pick · ⌥↩ copy only · ⌥P pin · ⌘, settings", 10 * S, c(pal, "secondary"))
    d.text((36 * S + 16 * S, cy + 150 * S), "Default shortcut", font=font(11 * S), fill=c(pal, "label"))
    caps = ["⌘", "⇧", "C"]
    widths = [keycap_width(d, cap, 24 * S) for cap in caps]
    kx = 36 * S + cw - 16 * S - (sum(widths) + 6 * S * (len(caps) - 1))
    for cap, ww in zip(caps, widths):
        draw_keycap(d, kx, cy + 142 * S, cap, pal, h=24 * S)
        kx += ww + 6 * S

    d.rectangle([0, h - 56 * S, w, h], fill=c(pal, "window"))
    d.rectangle([0, h - 56 * S, w, h - 56 * S + 1], fill=c(pal, "hairline"))
    d.text((36 * S, h - 36 * S), "4 / 8", font=font(11 * S), fill=c(pal, "secondary"))
    d.rectangle([w - 140 * S, h - 44 * S, w - 36 * S, h - 16 * S], fill=c(pal, "label"))
    d.text((w - 118 * S, h - 36 * S), "Continue", font=font(12 * S), fill=c(pal, "window"))
    return img


def contact_sheet(images: list[Image.Image], cols: int, label: str, pal: dict) -> Image.Image:
    gap = 20
    cw = max(im.width for im in images)
    ch = max(im.height for im in images)
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw + (cols + 1) * gap, rows * ch + (rows + 1) * gap + 48), c(pal, "desk"))
    d = ImageDraw.Draw(sheet)
    d.text((gap, 14), label, font=font(14), fill=(220, 220, 220) if pal is DARK else (30, 30, 30))
    for i, im in enumerate(images):
        r, cidx = divmod(i, cols)
        x = gap + cidx * (cw + gap) + (cw - im.width) // 2
        y = 48 + gap + r * (ch + gap) + (ch - im.height) // 2
        sheet.paste(im, (x, y))
    return sheet


def assert_usable(img: Image.Image, name: str) -> None:
    extrema = img.convert("L").getextrema()
    if extrema[0] == extrema[1]:
        raise SystemExit(f"FAIL {name}: blank")
    hist = img.convert("L").histogram()
    tones = sum(1 for v in hist if v > 0)
    if tones < 8:
        raise SystemExit(f"FAIL {name}: too few tones ({tones})")
    if img.width < 200 or img.height < 80:
        raise SystemExit(f"FAIL {name}: too small {img.size}")
    print(f"ok {name}: {img.size[0]}x{img.size[1]} tones={tones}")


def save(name: str, img: Image.Image) -> None:
    assert_usable(img, name)
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}-2x.png")
    img.save(OUT_MOCKS / f"{name}.png")
    print("wrote", name)


def main() -> None:
    assert DEPARTURE.exists(), DEPARTURE
    assert SYMBOL.exists() or SYMBOL_SANS.exists(), "DejaVu missing"
    for mode, pal in (("light", LIGHT), ("dark", DARK)):
        states = {
            f"clipboard-a-default-{mode}": render_default(pal),
            f"clipboard-a-selected-{mode}": render_selected(pal),
            f"clipboard-a-search-{mode}": render_search(pal),
            f"clipboard-a-empty-{mode}": render_empty(pal),
            f"clipboard-a-scroll-{mode}": render_scroll(pal),
            f"clipboard-a-preview-image-{mode}": render_preview_image(pal),
            f"clipboard-a-preview-text-{mode}": render_preview_text(pal),
            f"clipboard-a-settings-{mode}": render_settings(pal),
            f"clipboard-a-onboarding-keybinds-{mode}": render_onboarding_keybinds(pal),
            f"clipboard-a-onboarding-clipboard-{mode}": render_onboarding_clipboard(pal),
        }
        for name, img in states.items():
            save(name, img)

        sheet = contact_sheet(
            [states[f"clipboard-a-{s}-{mode}"] for s in ("default", "selected", "search", "empty", "scroll")],
            cols=3,
            label=f"clipboard A · refined states · {mode}",
            pal=pal,
        )
        save(f"clipboard-a-states-{mode}", sheet)

        sheet_p = contact_sheet(
            [states[f"clipboard-a-preview-image-{mode}"], states[f"clipboard-a-preview-text-{mode}"]],
            cols=2,
            label=f"clipboard A · preview popover · {mode}",
            pal=pal,
        )
        save(f"clipboard-a-preview-{mode}", sheet_p)

        sheet2 = contact_sheet(
            [
                states[f"clipboard-a-onboarding-keybinds-{mode}"],
                states[f"clipboard-a-onboarding-clipboard-{mode}"],
                states[f"clipboard-a-settings-{mode}"],
            ],
            cols=3,
            label=f"clipboard A · onboarding + settings · {mode}",
            pal=pal,
        )
        save(f"clipboard-a-onboarding-{mode}", sheet2)
    print("done")


if __name__ == "__main__":
    main()
