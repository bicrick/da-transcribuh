#!/usr/bin/env python3
"""Direction A clipboard design mocks — panel states, settings, onboarding (light+dark @2×)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)

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
    "pin": "#ED1C24",
    "thumb_a": "#3F48CC",
    "thumb_b": "#22B14C",
    "thumb_c": "#FF7F27",
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
    "pin": "#FF5A5F",
    "thumb_a": "#6B73E0",
    "thumb_b": "#3FD06A",
    "thumb_c": "#FF9A4D",
}

FOOTER = "↑↓ ⌃N⌃P · ↩ paste · ⌥↩ copy · ⌘1–9 · ⌥P pin · ⌥⌫ · Esc · ⌘,"

# kind: text | code | url | transcript | shot
DEFAULT_ROWS = [
    {"digit": "⌘1", "kind": "text", "preview": "API_BASE=https://api.local/v1", "tag": "", "pinned": True},
    {"digit": "⌘2", "kind": "code", "preview": "func paste() { simulateCommandV() }", "tag": "", "pinned": False},
    {"digit": "⌘3", "kind": "url", "preview": "https://github.com/bicrick/da-transcribuh", "tag": "", "pinned": False},
    {"digit": "⌘4", "kind": "transcript", "preview": "okay so the island bevel should invert…", "tag": "words", "pinned": False},
    {"digit": "⌘5", "kind": "shot", "preview": "Screenshot · Home bento", "tag": "tile", "pinned": False},
    {"digit": "⌘6", "kind": "text", "preview": "meeting notes — q3 roadmap draft", "tag": "", "pinned": False},
    {"digit": "⌘7", "kind": "transcript", "preview": "ship the compact clipboard panel first", "tag": "words", "pinned": False},
]

LONG_ROWS = [
    {"digit": f"⌘{i}" if i <= 9 else "", "kind": k, "preview": p, "tag": t, "pinned": pin}
    for i, (k, p, t, pin) in enumerate(
        [
            ("text", "API_BASE=https://api.local/v1", "", True),
            ("code", "guard chord.canRegister(allowingShift: true)", "", False),
            ("url", "https://docs.example.com/clipboard", "", False),
            ("transcript", "type straight into search, no click needed", "words", False),
            ("shot", "Screenshot · Appearance graphite", "tile", False),
            ("text", "patrick@da-transcribuh design review", "", False),
            ("code", "RegisterEventHotKey(/* id 4 */)", "", False),
            ("transcript", "Esc clears search then closes the panel", "words", False),
            ("shot", "Screenshot · recording island", "tile", False),
            ("text", "Maccy-like: ⌃N ⌃P move selection", "", False),
            ("url", "https://github.com/p0deje/Maccy", "", False),
            ("text", "pinned items stay above recents", "", False),
            ("transcript", "paste back uses Accessibility we already have", "words", False),
            ("shot", "Screenshot · Models picker", "tile", False),
            ("code", "NSPasteboard.general.changeCount", "", False),
        ],
        start=1,
    )
]


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def draw_bevel_panel(
    canvas: Image.Image,
    ox: int,
    oy: int,
    pw: int,
    ph: int,
    pal: dict,
) -> ImageDraw.ImageDraw:
    d = ImageDraw.Draw(canvas)
    d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    return d


def kind_glyph(kind: str) -> str:
    return {"text": "T", "code": "{", "url": "U", "transcript": "W", "shot": ""}.get(kind, "T")


def draw_thumb(d: ImageDraw.ImageDraw, x: int, y: int, size: int, pal: dict, variant: int) -> None:
    keys = ["thumb_a", "thumb_b", "thumb_c"]
    fill = c(pal, keys[variant % 3])
    d.rectangle([x, y, x + size, y + size], fill=fill, outline=c(pal, "label"), width=max(1, STROKE // 2))
    # faux window chrome
    d.rectangle([x + 2, y + 2, x + size - 2, y + size // 3], fill=c(pal, "fill"))


def draw_match_text(
    d: ImageDraw.ImageDraw,
    x: float,
    y: float,
    text: str,
    query: str,
    f: ImageFont.ImageFont,
    pal: dict,
    max_w: float,
) -> None:
    """Draw truncated preview with yellow highlight behind case-insensitive match span."""
    shown = text
    while text_size(d, shown + "…", f)[0] > max_w and len(shown) > 4:
        shown = shown[:-1]
    if shown != text:
        shown = shown.rstrip() + "…"

    q = query.lower()
    lower = shown.lower()
    idx = lower.find(q) if q else -1
    if idx < 0 or not q:
        d.text((x, y), shown, font=f, fill=c(pal, "label"))
        return

    before = shown[:idx]
    match = shown[idx : idx + len(q)]
    after = shown[idx + len(q) :]
    bx = x
    if before:
        d.text((bx, y), before, font=f, fill=c(pal, "label"))
        bx += text_size(d, before, f)[0]
    mw, mh = text_size(d, match, f)
    d.rectangle([bx - 1, y - 1, bx + mw + 1, y + mh + 2], fill=c(pal, "highlight"))
    d.text((bx, y), match, font=f, fill=c(pal, "label"))
    bx += mw
    if after:
        d.text((bx, y), after, font=f, fill=c(pal, "label"))


def draw_rows(
    d: ImageDraw.ImageDraw,
    ox: int,
    list_top: int,
    pw: int,
    row_h: float,
    rows: list[dict],
    pal: dict,
    selected: int,
    query: str = "",
    max_rows: int | None = None,
    fade_bottom: bool = False,
) -> float:
    visible = rows if max_rows is None else rows[:max_rows]
    y = float(list_top)
    f_digit = font(10 * S)
    f_body = font(12 * S)
    f_tag = font(9 * S)
    for i, row in enumerate(visible):
        bg = c(pal, "fill") if i == selected else c(pal, "front")
        d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + row_h], fill=bg)
        if i == selected:
            d.rectangle(
                [ox + STROKE + 1, y + 1, ox + pw - STROKE - 1, y + row_h - 1],
                outline=c(pal, "label"),
                width=STROKE,
            )

        # digit
        digit = row.get("digit") or ""
        if digit:
            d.text((ox + 10 * S, y + 13 * S), digit, font=f_digit, fill=c(pal, "secondary"))

        # kind / thumb
        gx = ox + 48 * S
        gy = y + 6 * S
        gsize = int(28 * S)
        if row["kind"] == "shot":
            draw_thumb(d, int(gx), int(gy), gsize, pal, i)
        else:
            d.rectangle([gx, gy, gx + gsize, gy + gsize], outline=c(pal, "label"), width=max(1, STROKE // 2))
            glyph = kind_glyph(row["kind"])
            gw, gh = text_size(d, glyph, font(12 * S))
            d.text((gx + (gsize - gw) / 2, gy + (gsize - gh) / 2 - 1), glyph, font=font(12 * S), fill=c(pal, "label"))

        # pin
        text_x = ox + 84 * S
        if row.get("pinned"):
            d.ellipse([text_x, y + 14 * S, text_x + 8 * S, y + 22 * S], fill=c(pal, "pin"))
            text_x += 12 * S

        # preview
        tag = row.get("tag") or ""
        right_pad = 12 * S
        if tag:
            tw, _ = text_size(d, tag, f_tag)
            right_pad += tw + 8 * S
            d.text((ox + pw - 12 * S - tw, y + 14 * S), tag, font=f_tag, fill=c(pal, "secondary"))
        max_w = ox + pw - right_pad - text_x
        draw_match_text(d, text_x, y + 12 * S, row["preview"], query, f_body, pal, max_w)

        y += row_h
        d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + 1], fill=c(pal, "hairline"))

    if fade_bottom:
        # scroll cue: partial next row + scroller thumb
        tip = list_top + (max_rows or 0) * row_h
        d.rectangle([ox + STROKE, tip, ox + pw - STROKE, tip + row_h * 0.45], fill=c(pal, "front"))
        d.text((ox + 84 * S, tip + 4 * S), "…", font=f_body, fill=c(pal, "tertiary"))
        track_x = ox + pw - 10 * S
        d.rectangle([track_x, list_top + 4, track_x + 6 * S, tip - 4], fill=c(pal, "fill"), outline=c(pal, "hairline"))
        d.rectangle([track_x, list_top + 4, track_x + 6 * S, list_top + 70 * S], fill=c(pal, "label"))

    return y


def panel_canvas(pal: dict, ph: float | None = None) -> tuple[Image.Image, ImageDraw.ImageDraw, int, int, int, int]:
    pw = int(360 * S)
    height = int((ph or 420) * S)
    margin = 28
    canvas = Image.new("RGB", (pw + BEVEL + margin * 2, height + BEVEL + margin * 2 + 36), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, pw, height, pal)
    return canvas, d, ox, oy, pw, height


def draw_search(d: ImageDraw.ImageDraw, ox: int, oy: int, pw: int, pal: dict, query: str, caret: bool = True) -> int:
    sh = int(36 * S)
    d.rectangle([ox, oy, ox + pw, oy + sh], fill=c(pal, "fill"))
    d.rectangle([ox, oy + sh - STROKE, ox + pw, oy + sh], fill=c(pal, "label"))
    label = f"⌕  {query}" if query else "⌕  Filter…"
    col = c(pal, "label") if query else c(pal, "secondary")
    d.text((ox + 12 * S, oy + 10 * S), label, font=font(12 * S), fill=col)
    if caret and query is not None:
        # block caret after query
        prefix = f"⌕  {query}"
        cw, ch = text_size(d, prefix, font(12 * S))
        d.rectangle(
            [ox + 12 * S + cw + 2, oy + 9 * S, ox + 12 * S + cw + 2 + 2 * S, oy + 9 * S + ch],
            fill=c(pal, "label"),
        )
    return sh


def draw_footer(d: ImageDraw.ImageDraw, ox: int, oy: int, pw: int, ph: int, pal: dict) -> None:
    fh = int(28 * S)
    fy = oy + ph - fh
    d.rectangle([ox, fy, ox + pw, oy + ph], fill=c(pal, "fill"))
    d.rectangle([ox, fy, ox + pw, fy + STROKE], fill=c(pal, "label"))
    d.text((ox + 8 * S, fy + 8 * S), FOOTER, font=font(8.5 * S), fill=c(pal, "secondary"))


def caption(canvas: Image.Image, pal: dict, text: str) -> None:
    d = ImageDraw.Draw(canvas)
    f = font(11 * S)
    tw, _ = text_size(d, text, f)
    d.text(((canvas.width - tw) / 2, canvas.height - 28), text, font=f, fill=(190, 190, 190))


def render_default(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal)
    sh = draw_search(d, ox, oy, pw, pal, "", caret=False)
    draw_rows(d, ox, oy + sh, pw, 40 * S, DEFAULT_ROWS, pal, selected=1)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, pal, "A · default · pinned top · ⌘⇧C")
    return canvas


def render_selected(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal)
    sh = draw_search(d, ox, oy, pw, pal, "", caret=False)
    draw_rows(d, ox, oy + sh, pw, 40 * S, DEFAULT_ROWS, pal, selected=3)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, pal, "A · selected row · ↑↓ / ⌃N ⌃P")
    return canvas


def render_search(pal: dict) -> Image.Image:
    query = "bevel"
    filtered = [
        {**r, "digit": f"⌘{i}"}
        for i, r in enumerate(
            [r for r in DEFAULT_ROWS + LONG_ROWS[7:9] if query.lower() in r["preview"].lower()],
            start=1,
        )
    ]
    # ensure we have a couple of bevel matches
    if len(filtered) < 2:
        filtered = [
            {"digit": "⌘1", "kind": "transcript", "preview": "okay so the island bevel should invert…", "tag": "words", "pinned": False},
            {"digit": "⌘2", "kind": "text", "preview": "Ink.bevel offset 3pt hard shadow", "tag": "", "pinned": False},
        ]
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=320)
    sh = draw_search(d, ox, oy, pw, pal, query, caret=True)
    draw_rows(d, ox, oy + sh, pw, 40 * S, filtered, pal, selected=0, query=query)
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, pal, "A · search · type-to-filter · match highlight")
    return canvas


def render_empty(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=280)
    sh = draw_search(d, ox, oy, pw, pal, "", caret=False)
    # empty body
    body_top = oy + sh
    body_bot = oy + ph - int(28 * S)
    mid_y = (body_top + body_bot) / 2
    msg = "No clipboard items yet"
    sub = "Copy text or finish a session."
    mw, mh = text_size(d, msg, font(13 * S))
    sw, _ = text_size(d, sub, font(11 * S))
    d.text((ox + (pw - mw) / 2, mid_y - 18 * S), msg, font=font(13 * S), fill=c(pal, "secondary"))
    d.text((ox + (pw - sw) / 2, mid_y + 6 * S), sub, font=font(11 * S), fill=c(pal, "tertiary"))
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, pal, "A · empty state")
    return canvas


def render_scroll(pal: dict) -> Image.Image:
    canvas, d, ox, oy, pw, ph = panel_canvas(pal, ph=420)
    sh = draw_search(d, ox, oy, pw, pal, "", caret=False)
    draw_rows(
        d,
        ox,
        oy + sh,
        pw,
        40 * S,
        LONG_ROWS,
        pal,
        selected=2,
        max_rows=8,
        fade_bottom=True,
    )
    draw_footer(d, ox, oy, pw, ph, pal)
    caption(canvas, pal, "A · long list · scroll thumb")
    return canvas


def _wrap_lines(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont, max_w: float) -> list[str]:
    words = text.split()
    if not words:
        return [""]
    lines: list[str] = []
    cur = words[0]
    for w in words[1:]:
        trial = f"{cur} {w}"
        if text_size(draw, trial, f)[0] <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def draw_preview_popover(
    canvas: Image.Image,
    px: int,
    py: int,
    pal: dict,
    *,
    mode: str,
    body_lines: list[str] | None = None,
    image_variant: int = 0,
    source: str,
    first: str,
    last: str,
    copies: str,
) -> tuple[int, int]:
    """Draw popover; returns (width, height) of popover face."""
    pop_w = int(300 * S)
    pad = int(14 * S)
    meta_h = int(108 * S)
    preview_h = int(160 * S) if mode == "image" else int(140 * S)
    pop_h = pad + preview_h + int(10 * S) + meta_h + pad
    d = ImageDraw.Draw(canvas)
    # bevel + face
    d.rectangle([px + BEVEL, py + BEVEL, px + pop_w + BEVEL, py + pop_h + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([px, py, px + pop_w, py + pop_h], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)

    ix, iy = px + pad, py + pad
    iw, ih = pop_w - 2 * pad, preview_h
    if mode == "image":
        # faux screenshot preview
        d.rectangle([ix, iy, ix + iw, iy + ih], fill=c(pal, "fill"), outline=c(pal, "label"), width=STROKE)
        # inner "UI" chrome
        d.rectangle([ix + 8 * S, iy + 8 * S, ix + iw - 8 * S, iy + 28 * S], fill=c(pal, "window"))
        d.rectangle([ix + 8 * S, iy + 28 * S, ix + iw - 8 * S, iy + ih - 8 * S], fill=c(pal, "front"))
        # accent blocks like a bento / island
        colors = [c(pal, "thumb_a"), c(pal, "thumb_b"), c(pal, "thumb_c")]
        bx = ix + 16 * S
        by = iy + 40 * S
        for i in range(3):
            d.rectangle(
                [bx + i * 70 * S, by, bx + i * 70 * S + 60 * S, by + 48 * S],
                fill=colors[(i + image_variant) % 3],
                outline=c(pal, "label"),
                width=max(1, STROKE // 2),
            )
        d.rectangle(
            [ix + 16 * S, by + 60 * S, ix + iw - 16 * S, iy + ih - 16 * S],
            fill=c(pal, "fill"),
            outline=c(pal, "hairline"),
        )
        d.text((ix + 24 * S, by + 72 * S), "Home · bento layout", font=font(11 * S), fill=c(pal, "label"))
    else:
        d.rectangle([ix, iy, ix + iw, iy + ih], fill=c(pal, "fill"), outline=c(pal, "hairline"))
        f = font(11 * S)
        ty = iy + 10 * S
        lines = body_lines or []
        for line in lines:
            for wrapped in _wrap_lines(d, line, f, iw - 16 * S):
                if ty + 14 * S > iy + ih - 8 * S:
                    d.text((ix + 8 * S, ty), "…", font=f, fill=c(pal, "tertiary"))
                    break
                d.text((ix + 8 * S, ty), wrapped, font=f, fill=c(pal, "label"))
                ty += 15 * S
            else:
                continue
            break

    # metadata
    my = iy + preview_h + int(10 * S)
    d.rectangle([px + STROKE, my, px + pop_w - STROKE, my + 1], fill=c(pal, "hairline"))
    my += 10 * S
    f_meta = font(10 * S)
    rows = [
        ("Source", source),
        ("First copy", first),
        ("Last copy", last),
        ("Copies", copies),
        ("", "⌥P pin/unpin · ⌥⌫ delete"),
    ]
    for label, value in rows:
        if label:
            d.text((px + pad, my), f"{label}", font=f_meta, fill=c(pal, "tertiary"))
            d.text((px + pad + 88 * S, my), value, font=f_meta, fill=c(pal, "label"))
        else:
            d.text((px + pad, my + 4 * S), value, font=font(9 * S), fill=c(pal, "secondary"))
        my += 16 * S
    return pop_w, pop_h


def render_preview_image(pal: dict) -> Image.Image:
    """List + preview popover for a screenshot row."""
    list_pw = int(360 * S)
    list_ph = int(420 * S)
    margin = 24
    gap = int(10 * S)
    pop_w = int(300 * S)
    pop_h = int(300 * S)
    W = margin * 2 + list_pw + BEVEL + gap + pop_w + BEVEL
    H = margin * 2 + max(list_ph + BEVEL, pop_h + BEVEL) + 40
    canvas = Image.new("RGB", (W, H), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, list_pw, list_ph, pal)
    sh = draw_search(d, ox, oy, list_pw, pal, "", caret=False)
    # select screenshot row (index 4 in DEFAULT_ROWS)
    draw_rows(d, ox, oy + sh, list_pw, 40 * S, DEFAULT_ROWS, pal, selected=4)
    draw_footer(d, ox, oy, list_pw, list_ph, pal)

    # popover to the right, aligned near selected row (~row 4)
    row_y = oy + sh + 4 * 40 * S
    px = ox + list_pw + BEVEL + gap
    py = max(margin, min(row_y - 40 * S, H - margin - pop_h - 40))
    draw_preview_popover(
        canvas,
        px,
        int(py),
        pal,
        mode="image",
        image_variant=1,
        source="da transcribuh · screenshot",
        first="Today 2:14 PM",
        last="Today 2:14 PM",
        copies="1",
    )
    caption(canvas, pal, "A · preview popover · image · ~400ms after select")
    return canvas


def render_preview_text(pal: dict) -> Image.Image:
    """List + preview popover for a code/text row."""
    list_pw = int(360 * S)
    list_ph = int(420 * S)
    margin = 24
    gap = int(10 * S)
    pop_w = int(300 * S)
    pop_h = int(290 * S)
    W = margin * 2 + list_pw + BEVEL + gap + pop_w + BEVEL
    H = margin * 2 + max(list_ph + BEVEL, pop_h + BEVEL) + 40
    canvas = Image.new("RGB", (W, H), c(pal, "desk"))
    ox, oy = margin, margin
    d = draw_bevel_panel(canvas, ox, oy, list_pw, list_ph, pal)
    sh = draw_search(d, ox, oy, list_pw, pal, "", caret=False)
    # select code row (index 1)
    draw_rows(d, ox, oy + sh, list_pw, 40 * S, DEFAULT_ROWS, pal, selected=1)
    draw_footer(d, ox, oy, list_pw, list_ph, pal)

    row_y = oy + sh + 1 * 40 * S
    px = ox + list_pw + BEVEL + gap
    py = max(margin, min(row_y - 20 * S, H - margin - pop_h - 40))
    code_body = [
        "func paste() {",
        "  simulateCommandV()",
        "}",
        "",
        "// HotkeyChord.canRegister(allowingShift: true)",
        "// ⌘⇧C opens history beside the cursor",
    ]
    draw_preview_popover(
        canvas,
        px,
        int(py),
        pal,
        mode="text",
        body_lines=code_body,
        source="Cursor",
        first="Yesterday 6:02 PM",
        last="Today 11:08 AM",
        copies="4",
    )
    caption(canvas, pal, "A · preview popover · text/code · hover or ⌃N")
    return canvas


def render_settings(pal: dict) -> Image.Image:
    w, h = int(520 * S), int(360 * S)
    img = Image.new("RGB", (w + 40, h + 60), c(pal, "desk"))
    d = ImageDraw.Draw(img)
    ox, oy = 20, 20
    # page
    d.rectangle([ox, oy, ox + w, oy + h], fill=c(pal, "window"))
    d.text((ox + 24 * S, oy + 20 * S), "General", font=font(18 * S), fill=c(pal, "label"))
    d.text(
        (ox + 24 * S, oy + 48 * S),
        "Shortcuts, launch behavior, and paste rules.",
        font=font(11 * S),
        fill=c(pal, "secondary"),
    )
    # card with bevel
    cx, cy = ox + 24 * S, oy + 80 * S
    cw, ch = w - 48 * S, int(220 * S)
    d.rectangle([cx + BEVEL, cy + BEVEL, cx + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([cx, cy, cx + cw, cy + ch], fill=c(pal, "card"), outline=c(pal, "label"), width=STROKE)
    d.text((cx + 16 * S, cy + 14 * S), "Clipboard", font=font(13 * S), fill=c(pal, "label"))
    d.text(
        (cx + 16 * S, cy + 36 * S),
        "Maccy-style history. Uses Accessibility (already needed for paste).",
        font=font(10 * S),
        fill=c(pal, "secondary"),
    )
    # toggle row
    ry = cy + 64 * S
    d.rectangle([cx, ry, cx + cw, ry + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry + 14 * S), "Enable clipboard history", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + 16 * S, ry + 34 * S), "On by default. ⌘⇧C opens the panel near the pointer.", font=font(10 * S), fill=c(pal, "secondary"))
    # fake toggle on
    tx = cx + cw - 52 * S
    d.rectangle([tx, ry + 18 * S, tx + 36 * S, ry + 36 * S], fill=c(pal, "label"), outline=c(pal, "label"), width=STROKE)
    d.rectangle([tx + 18 * S, ry + 20 * S, tx + 34 * S, ry + 34 * S], fill=c(pal, "front"))

    ry2 = ry + 56 * S
    d.rectangle([cx, ry2, cx + cw, ry2 + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry2 + 14 * S), "Shortcut", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + 16 * S, ry2 + 34 * S), "click to rebind", font=font(10 * S), fill=c(pal, "secondary"))
    # keycaps
    caps = ["⌘", "⇧", "C"]
    kx = cx + cw - 16 * S - len(caps) * 28 * S
    for i, cap in enumerate(caps):
        x = kx + i * 28 * S
        d.rectangle([x, ry2 + 16 * S, x + 24 * S, ry2 + 40 * S], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
        tw, th = text_size(d, cap, font(11 * S))
        d.text((x + (24 * S - tw) / 2, ry2 + 16 * S + (24 * S - th) / 2), cap, font=font(11 * S), fill=c(pal, "label"))

    ry3 = ry2 + 56 * S
    d.rectangle([cx, ry3, cx + cw, ry3 + 1], fill=c(pal, "hairline"))
    d.text((cx + 16 * S, ry3 + 14 * S), "History limit", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + cw - 48 * S, ry3 + 14 * S), "200", font=font(12 * S), fill=c(pal, "label"))
    d.text((cx + 16 * S, ry3 + 44 * S), "Reset to ⌘⇧C", font=font(11 * S), fill=c(pal, "secondary"))
    d.text((cx + 140 * S, ry3 + 44 * S), "Clear history", font=font(11 * S), fill=c(pal, "secondary"))

    caption(img, pal, "settings · General · Clipboard")
    return img


def render_onboarding_keybinds(pal: dict) -> Image.Image:
    w, h = int(560 * S), int(480 * S)
    img = Image.new("RGB", (w, h), c(pal, "window"))
    d = ImageDraw.Draw(img)
    # title strip
    d.text((0, 0), "", font=font(1))  # warm font cache
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
    d.text(
        (36 * S, 122 * S),
        "Recording defaults to ⌥Space. Clipboard history uses ⌘⇧C.",
        font=font(12 * S),
        fill=c(pal, "secondary"),
    )
    d.text(
        (36 * S, 146 * S),
        "⌘Space and ⌥⌘Space stay with the system.",
        font=font(12 * S),
        fill=c(pal, "secondary"),
    )

    def chord_card(cy: float, title: str, hint: str, caps: list[str]) -> None:
        cw = w - 72 * S
        ch = 88 * S
        d.rectangle([36 * S + BEVEL, cy + BEVEL, 36 * S + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
        d.rectangle([36 * S, cy, 36 * S + cw, cy + ch], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
        d.text((36 * S + 16 * S, cy + 14 * S), title, font=font(12 * S), fill=c(pal, "label"))
        d.text((36 * S + 16 * S, cy + 36 * S), hint, font=font(10 * S), fill=c(pal, "secondary"))
        kx = 36 * S + cw - 16 * S - len(caps) * 28 * S
        for i, cap in enumerate(caps):
            x0 = kx + i * 28 * S
            d.rectangle(
                [x0, cy + 28 * S, x0 + 24 * S, cy + 52 * S],
                fill=c(pal, "front"),
                outline=c(pal, "label"),
                width=STROKE,
            )
            tw2, th2 = text_size(d, cap, font(11 * S))
            d.text((x0 + (24 * S - tw2) / 2, cy + 28 * S + (24 * S - th2) / 2), cap, font=font(11 * S), fill=c(pal, "label"))
        d.text((36 * S + 16 * S, cy + 62 * S), "Change", font=font(11 * S), fill=c(pal, "secondary"))

    chord_card(180 * S, "Recording", "click to rebind", ["⌥", "Space"])
    chord_card(286 * S, "Clipboard history", "click to rebind", ["⌘", "⇧", "C"])

    # footer buttons
    d.rectangle([0, h - 56 * S, w, h], fill=c(pal, "window"))
    d.rectangle([0, h - 56 * S, w, h - 56 * S + 1], fill=c(pal, "hairline"))
    d.text((36 * S, h - 36 * S), "3 / 8", font=font(11 * S), fill=c(pal, "secondary"))
    d.rectangle([w - 140 * S, h - 44 * S, w - 36 * S, h - 16 * S], fill=c(pal, "label"))
    d.text((w - 118 * S, h - 36 * S), "Continue", font=font(12 * S), fill=c(pal, "window"))
    return img


def render_onboarding_clipboard(pal: dict) -> Image.Image:
    w, h = int(560 * S), int(480 * S)
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
    lines = [
        "Compact list at the cursor. Type to search, Enter pastes.",
        "Copies, transcripts, and screenshots land here.",
        "Accessibility for paste already covers this — nothing new to grant.",
    ]
    by = 122 * S
    for line in lines:
        d.text((36 * S, by), line, font=font(12 * S), fill=c(pal, "secondary"))
        by += 22 * S

    # card: toggle + mini panel teaser
    cy = by + 12 * S
    cw = w - 72 * S
    ch = 180 * S
    d.rectangle([36 * S + BEVEL, cy + BEVEL, 36 * S + cw + BEVEL, cy + ch + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([36 * S, cy, 36 * S + cw, cy + ch], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    d.text((36 * S + 16 * S, cy + 16 * S), "Enable clipboard history", font=font(12 * S), fill=c(pal, "label"))
    d.text((36 * S + 16 * S, cy + 38 * S), "On by default. Off anytime in General.", font=font(10 * S), fill=c(pal, "secondary"))
    tx = 36 * S + cw - 52 * S
    d.rectangle([tx, cy + 20 * S, tx + 36 * S, cy + 38 * S], fill=c(pal, "label"), outline=c(pal, "label"), width=STROKE)
    d.rectangle([tx + 18 * S, cy + 22 * S, tx + 34 * S, cy + 36 * S], fill=c(pal, "front"))

    d.rectangle([36 * S, cy + 56 * S, 36 * S + cw, cy + 56 * S + 1], fill=c(pal, "hairline"))
    d.text((36 * S + 16 * S, cy + 70 * S), "Keyboard", font=font(11 * S), fill=c(pal, "label"))
    d.text((36 * S + 16 * S, cy + 92 * S), "Type → filter   ↑↓ → move   ↩ → paste   Esc → clear / close", font=font(10 * S), fill=c(pal, "secondary"))
    d.text((36 * S + 16 * S, cy + 118 * S), "⌘1–9 instant pick · ⌥↩ copy only · ⌥P pin · ⌘, settings", font=font(10 * S), fill=c(pal, "secondary"))
    d.text((36 * S + 16 * S, cy + 148 * S), "Default shortcut", font=font(11 * S), fill=c(pal, "label"))
    caps = ["⌘", "⇧", "C"]
    kx = 36 * S + cw - 16 * S - len(caps) * 28 * S
    for i, cap in enumerate(caps):
        x0 = kx + i * 28 * S
        d.rectangle([x0, cy + 140 * S, x0 + 24 * S, cy + 164 * S], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
        tw2, th2 = text_size(d, cap, font(11 * S))
        d.text((x0 + (24 * S - tw2) / 2, cy + 140 * S + (24 * S - th2) / 2), cap, font=font(11 * S), fill=c(pal, "label"))

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
    sheet = Image.new(
        "RGB",
        (cols * cw + (cols + 1) * gap, rows * ch + (rows + 1) * gap + 48),
        c(pal, "desk"),
    )
    d = ImageDraw.Draw(sheet)
    d.text((gap, 14), label, font=font(14), fill=(220, 220, 220) if pal is DARK else (30, 30, 30))
    for i, im in enumerate(images):
        r, cidx = divmod(i, cols)
        x = gap + cidx * (cw + gap) + (cw - im.width) // 2
        y = 48 + gap + r * (ch + gap) + (ch - im.height) // 2
        sheet.paste(im, (x, y))
    return sheet


def save(name: str, img: Image.Image) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}-2x.png")
    img.save(OUT_MOCKS / f"{name}.png")
    print("wrote", name)


def main() -> None:
    assert DEPARTURE.exists(), f"missing font {DEPARTURE}"
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

        panel_states = [
            states[f"clipboard-a-default-{mode}"],
            states[f"clipboard-a-selected-{mode}"],
            states[f"clipboard-a-search-{mode}"],
            states[f"clipboard-a-empty-{mode}"],
            states[f"clipboard-a-scroll-{mode}"],
        ]
        sheet = contact_sheet(panel_states, cols=3, label=f"clipboard A · states · {mode}", pal=pal)
        save(f"clipboard-a-states-{mode}", sheet)

        previews = [
            states[f"clipboard-a-preview-image-{mode}"],
            states[f"clipboard-a-preview-text-{mode}"],
        ]
        sheet_p = contact_sheet(previews, cols=2, label=f"clipboard A · preview popover · {mode}", pal=pal)
        save(f"clipboard-a-preview-{mode}", sheet_p)

        onb = [
            states[f"clipboard-a-onboarding-keybinds-{mode}"],
            states[f"clipboard-a-onboarding-clipboard-{mode}"],
            states[f"clipboard-a-settings-{mode}"],
        ]
        sheet2 = contact_sheet(onb, cols=3, label=f"clipboard A · onboarding + settings · {mode}", pal=pal)
        save(f"clipboard-a-onboarding-{mode}", sheet2)

    print("done")


if __name__ == "__main__":
    main()
