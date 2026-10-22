#!/usr/bin/env python3
"""Render clipboard history panel mocks: light/dark, default + scrolled (gutter + thumb)."""

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
# Match Ink scroller tokens
SCROLLER_W = int(10 * S)
SCROLLER_GAP = int(4 * S)
SCROLLER_INSET = int(2 * S)
THUMB_MIN = int(24 * S)

LIGHT = {
    "desk": "#5A5A5A",
    "window": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "select_bg": "#000000",
    "select_fg": "#FFFFFF",
}
DARK = {
    "desk": "#1A1A1C",
    "window": "#2C2C2E",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#F2F2F2",
    "select_bg": "#F2F2F2",
    "select_fg": "#2C2C2E",
}


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return rgb(pal[key])


def draw_search_glyph(d: ImageDraw.ImageDraw, x: float, y: float, size: float, color: tuple[int, int, int]) -> None:
    """Drawn magnifying glass — same idea as ClipboardSearchGlyph (no ⌕ tofu)."""
    stroke = max(2, int(1.5 * S))
    glass = size * 0.62
    d.ellipse([x, y, x + glass, y + glass], outline=color, width=stroke)
    d.line(
        [x + glass * 0.72, y + glass * 0.72, x + size - 1, y + size - 1],
        fill=color,
        width=stroke,
    )


ROWS = [
    ("API_KEY=sk-••••", True),
    ("func paste() { simulateCommandV() }", True),
    ("https://github.com/bicrick/da-transcribuh", False),
    ("okay so the island bevel should invert in dark mode…", False),
    ("meeting notes — q3 roadmap and follow-ups", False),
    ("prompt: keep Departure Mono everywhere in chrome", False),
    ("Screenshot tile — history scroller proof", False),
    ("⌥Space starts and stops a session", False),
    ("clipboard history opens with ⌘⇧C", False),
    ("trim pinned rows survive Clear", False),
    ("fingerprint dedupe bumps copyCount", False),
    ("Accessibility paste stages then ⌘V", False),
    ("empty quiet takes never land here", False),
    ("graphite dark uses #F2F2F2 bevel", False),
    ("double-pane chrome gutter Ink.bevelOffset", False),
    ("row sixteen for scroll travel", False),
]


def draw_panel(pal: dict, scroll_frac: float) -> Image.Image:
    pw, ph = int(450 * S), int(480 * S)
    canvas = Image.new("RGB", (pw + BEVEL + 48, ph + BEVEL + 64), c(pal, "desk"))
    d = ImageDraw.Draw(canvas)
    ox, oy = 24, 24
    d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "window"), outline=c(pal, "label"), width=STROKE)

    # Header
    header_h = int(40 * S)
    d.rectangle([ox, oy, ox + pw, oy + header_h], fill=c(pal, "fill"))
    title = "clipboard"
    tf = font(11 * S)
    d.text((ox + int(12 * S), oy + int(12 * S)), title, font=tf, fill=c(pal, "secondary"))
    field_w, field_h = int(220 * S), int(23 * S)
    fx = ox + pw - int(12 * S) - field_w
    fy = oy + (header_h - field_h) // 2
    d.rectangle([fx, fy, fx + field_w, fy + field_h], fill=c(pal, "window"), outline=c(pal, "label"), width=STROKE)
    draw_search_glyph(d, fx + int(6 * S), fy + int(5 * S), int(11 * S), c(pal, "secondary"))
    d.text((fx + int(22 * S), fy + int(4 * S)), "type to search…", font=font(12 * S), fill=c(pal, "secondary"))

    # List region (content | gap | track)
    list_top = oy + header_h
    footer_h = int(72 * S)
    list_bottom = oy + ph - footer_h
    view_h = list_bottom - list_top
    row_h = int(22 * S)
    content_h = len(ROWS) * row_h
    gutter = SCROLLER_GAP + SCROLLER_W
    content_right = ox + pw - gutter - int(4 * S)

    scrollable = max(content_h - view_h, 0)
    offset = scroll_frac * scrollable
    first = int(offset // row_h)
    y_off = -(offset % row_h)

    # Clip list by drawing only in band
    selected = first + 2 if first + 2 < len(ROWS) else len(ROWS) - 1
    y = list_top + y_off
    for i in range(first, len(ROWS)):
        if y > list_bottom:
            break
        text, pinned = ROWS[i]
        if y + row_h < list_top:
            y += row_h
            continue
        # clip row to list band
        row_y0 = max(y, list_top)
        row_y1 = min(y + row_h, list_bottom)
        if i == selected:
            d.rectangle([ox + STROKE, row_y0, content_right, row_y1], fill=c(pal, "select_bg"))
            fg = c(pal, "select_fg")
        else:
            fg = c(pal, "label")
        label = ("• " if pinned else "") + text
        d.text((ox + int(16 * S), y + int(4 * S)), label[:42], font=font(11 * S), fill=fg)
        if i - first < 9:
            shortcut = f"⌘{i - first + 1}"
            sw = d.textlength(shortcut, font=font(10 * S))
            d.text(
                (content_right - sw - int(8 * S), y + int(5 * S)),
                shortcut,
                font=font(10 * S),
                fill=c(pal, "secondary") if i != selected else fg,
            )
        y += row_h

    # Scroller track in reserved gutter
    track_x = ox + pw - SCROLLER_W - SCROLLER_INSET
    track_top = list_top + SCROLLER_INSET
    track_bot = list_bottom - SCROLLER_INSET
    track_h = max(track_bot - track_top, 1)
    d.rectangle(
        [track_x, track_top, track_x + SCROLLER_W, track_bot],
        fill=c(pal, "window"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    ratio = min(1.0, view_h / max(content_h, 1))
    thumb_h = max(THUMB_MIN, track_h * ratio)
    travel = max(track_h - thumb_h, 0)
    thumb_y = track_top + (offset / scrollable if scrollable else 0) * travel
    d.rectangle(
        [track_x, thumb_y, track_x + SCROLLER_W, thumb_y + thumb_h],
        fill=c(pal, "label"),
        outline=c(pal, "label"),
        width=STROKE,
    )

    # Footer
    fy0 = list_bottom
    d.rectangle([ox, fy0, ox + pw, oy + ph], fill=c(pal, "fill"))
    d.line([ox, fy0, ox + pw, fy0], fill=c(pal, "hairline"), width=1)
    for i, label in enumerate(["Clear", "Preferences…", "Quit"]):
        d.text(
            (ox + int(16 * S), fy0 + int(8 * S) + i * int(18 * S)),
            label,
            font=font(11 * S),
            fill=c(pal, "label"),
        )

    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    for name, pal in (("light", LIGHT), ("dark", DARK)):
        for state, frac in (("default", 0.0), ("scrolled", 0.55)):
            img = draw_panel(pal, frac)
            art = OUT / f"clipboard-panel-{state}-{name}-2x.png"
            mock = OUT_MOCKS / f"clipboard-panel-{state}-{name}.png"
            img.save(art)
            img.save(mock)
            print("wrote", art.name, img.size)
        # strip: default | scrolled
        a = Image.open(OUT / f"clipboard-panel-default-{name}-2x.png")
        b = Image.open(OUT / f"clipboard-panel-scrolled-{name}-2x.png")
        gap = 24
        strip = Image.new("RGB", (a.width + b.width + gap, max(a.height, b.height)), c(pal, "desk"))
        strip.paste(a, (0, 0))
        strip.paste(b, (a.width + gap, 0))
        strip.save(OUT / f"clipboard-panel-strip-{name}-2x.png")
        strip.save(OUT_MOCKS / f"clipboard-panel-strip-{name}.png")
        print("wrote strip", name, strip.size)


if __name__ == "__main__":
    main()
