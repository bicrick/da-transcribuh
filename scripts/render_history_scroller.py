#!/usr/bin/env python3
"""History table scroller mocks — gutter reserved, thumb tracks top/mid/bottom.

Light + graphite dark @2×. Proves content never sits under the thumb and the
thumb moves with scroll offset.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"
OUT_ART = Path("/opt/cursor/artifacts")

S = 2.0
STROKE = int(2 * S)
# Ink.scrollerWidth 10 + gutterGap 4
TRACK_W = int(10 * S)
GUTTER_GAP = int(4 * S)
GUTTER = GUTTER_GAP + TRACK_W
THUMB_MIN = int(24 * S)
ROW_H = int(40 * S)
HEADER_H = int(28 * S)
ROWS = 16  # enough to scroll in a ~320pt viewport
VIEW_H = int(280 * S)
TABLE_W = int(860 * S)


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


LIGHT = {
    "window": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
    "hairline": "#C0C0C0",
    "front": "#FFFFFF",
}

DARK = {
    "window": "#2C2C2E",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "front": "#3A3A3D",
}


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def text_w(d: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> int:
    bb = d.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0]


def draw_table(pal: dict, scroll_frac: float, label: str) -> Image.Image:
    content_h = ROWS * ROW_H
    scrollable = max(content_h - VIEW_H, 1)
    offset = scroll_frac * scrollable

    pad = int(24 * S)
    title_h = int(36 * S)
    W = TABLE_W + pad * 2
    H = title_h + HEADER_H + VIEW_H + pad * 2
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)

    d.text((pad, pad), f"history · scroller {label}", font=font(14 * S), fill=c(pal, "secondary"))

    tx = pad
    ty = pad + title_h
    # Outer table frame
    d.rectangle(
        [tx, ty, tx + TABLE_W, ty + HEADER_H + VIEW_H],
        outline=c(pal, "label"),
        width=STROKE,
    )

    # Header — trailing gutter so ACT aligns with rows
    d.rectangle([tx, ty, tx + TABLE_W, ty + HEADER_H], fill=c(pal, "fill"))
    cols = [
        (132, "WHEN"),
        (56, "DUR"),
        (52, "TILES"),
        (64, "WORDS"),
    ]
    x = tx
    for w, name in cols:
        d.text((x + 8 * S, ty + 8 * S), name, font=font(11 * S), fill=c(pal, "secondary"))
        x += w * S
    d.text((x + 8 * S, ty + 8 * S), "TEXT", font=font(11 * S), fill=c(pal, "secondary"))
    act = "ACT"
    aw = text_w(d, act, font(11 * S))
    # ACT sits left of reserved gutter
    d.text(
        (tx + TABLE_W - GUTTER - 8 * S - aw, ty + 8 * S),
        act,
        font=font(11 * S),
        fill=c(pal, "secondary"),
    )
    d.rectangle([tx, ty + HEADER_H - 1, tx + TABLE_W, ty + HEADER_H], fill=c(pal, "label"))

    # Viewport clip for rows
    view_top = ty + HEADER_H
    content_w = TABLE_W - GUTTER
    # Row strip
    first = int(offset // ROW_H)
    y_off = -(offset % ROW_H)
    samples = [
        "Ship the folder tabs and keep Start inverted.",
        "Dictate standup notes while capturing the board.",
        "Paste the sheet under the notes.",
        "Quick reply about the notarized build.",
        "Island bevel should invert in dark mode.",
        "Wire Accessibility paste follow-up path.",
        "Chord editor click to rebind live.",
        "Contact sheet thumbnail for History.",
    ]
    for i in range(first, ROWS + 2):
        ry = view_top + y_off + (i - first) * ROW_H
        if ry > view_top + VIEW_H:
            break
        if ry + ROW_H < view_top:
            continue
        # clip draw by intersecting — simple: only draw if mostly visible
        row_y = max(ry, view_top)
        preview = samples[i % len(samples)]
        when = f"Oct {10 + (i % 12):02d}"
        # background
        bg = c(pal, "fill") if i % 2 == 0 else c(pal, "front")
        d.rectangle([tx + STROKE, row_y, tx + content_w, min(ry + ROW_H, view_top + VIEW_H)], fill=bg)
        if ry >= view_top and ry + 20 * S <= view_top + VIEW_H:
            d.text((tx + 8 * S, ry + 12 * S), when, font=font(11 * S), fill=c(pal, "label"))
            d.text((tx + 140 * S, ry + 12 * S), "0:42", font=font(11 * S), fill=c(pal, "secondary"))
            d.text((tx + 200 * S, ry + 12 * S), f"{(i % 5)}", font=font(11 * S), fill=c(pal, "secondary"))
            d.text((tx + 260 * S, ry + 12 * S), f"{20 + i}", font=font(11 * S), fill=c(pal, "secondary"))
            d.text((tx + 340 * S, ry + 12 * S), preview[:42], font=font(11 * S), fill=c(pal, "label"))
            # Show button — must stay left of gutter
            bw, bh = int(48 * S), int(22 * S)
            bx = tx + content_w - 8 * S - bw
            by = ry + 8 * S
            if by + bh <= view_top + VIEW_H:
                d.rectangle([bx, by, bx + bw, by + bh], outline=c(pal, "label"), width=STROKE, fill=c(pal, "front"))
                tw = text_w(d, "Show", font(11 * S))
                d.text((bx + (bw - tw) / 2, by + 4 * S), "Show", font=font(11 * S), fill=c(pal, "label"))

    # Cover anything that spilled under header / below viewport
    d.rectangle([tx, ty, tx + TABLE_W, view_top], fill=c(pal, "fill"))
    # redraw header text quickly
    x = tx
    for w, name in cols:
        d.text((x + 8 * S, ty + 8 * S), name, font=font(11 * S), fill=c(pal, "secondary"))
        x += w * S
    d.text((x + 8 * S, ty + 8 * S), "TEXT", font=font(11 * S), fill=c(pal, "secondary"))
    d.text(
        (tx + TABLE_W - GUTTER - 8 * S - aw, ty + 8 * S),
        act,
        font=font(11 * S),
        fill=c(pal, "secondary"),
    )
    d.rectangle([tx, ty + HEADER_H - 1, tx + TABLE_W, ty + HEADER_H], fill=c(pal, "label"))
    d.rectangle(
        [tx, view_top + VIEW_H, tx + TABLE_W, ty + HEADER_H + VIEW_H + 2],
        fill=c(pal, "window"),
    )

    # Gutter + track + thumb (full height of scroll area — flush with header
    # divider and bottom border; no scrollerInset gaps).
    gx = tx + content_w + GUTTER_GAP
    track_top = view_top
    track_h = VIEW_H
    d.rectangle(
        [gx, track_top, gx + TRACK_W, track_top + track_h],
        fill=c(pal, "window"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    # Same formula as DTScrollGeometry.thumbHeight / thumbY
    ratio = min(1.0, VIEW_H / max(content_h, 1))
    thumb_h = max(THUMB_MIN, track_h * ratio)
    scrollable = max(content_h - VIEW_H, 0)
    travel = max(track_h - thumb_h, 0)
    offset = scroll_frac * scrollable
    fraction = (offset / scrollable) if scrollable > 0 else 0.0
    thumb_y = track_top + fraction * travel
    d.rectangle(
        [gx, thumb_y, gx + TRACK_W, thumb_y + thumb_h],
        fill=c(pal, "label"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    # Prove thumb moved: encode expected Y in a side label for reviewers.
    d.text(
        (pad, H - 20 * S),
        f"offset={offset:.0f} thumbY={fraction * travel:.0f} content={content_h:.0f} view={VIEW_H:.0f}",
        font=font(9 * S),
        fill=c(pal, "secondary"),
    )

    # Outer stroke again
    d.rectangle(
        [tx, ty, tx + TABLE_W, ty + HEADER_H + VIEW_H],
        outline=c(pal, "label"),
        width=STROKE,
    )
    return img


def main() -> None:
    assert DEPARTURE.exists()
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    OUT_ART.mkdir(parents=True, exist_ok=True)
    positions = [("top", 0.0), ("mid", 0.45), ("bottom", 1.0)]
    for theme, pal in (("light", LIGHT), ("dark", DARK)):
        strips = []
        for name, frac in positions:
            img = draw_table(pal, frac, name)
            path = OUT_MOCKS / f"history-scroller-{name}-{theme}.png"
            img.save(path)
            img.save(OUT_ART / f"history-scroller-{name}-{theme}-2x.png")
            strips.append(img)
            print("wrote", path.name, img.size)
        # Contact strip
        gap = int(16 * S)
        w = sum(i.width for i in strips) + gap * (len(strips) - 1)
        h = max(i.height for i in strips)
        sheet = Image.new("RGB", (w, h), c(pal, "window"))
        x = 0
        for i in strips:
            sheet.paste(i, (x, 0))
            x += i.width + gap
        sheet.save(OUT_MOCKS / f"history-scroller-strip-{theme}.png")
        sheet.save(OUT_ART / f"history-scroller-strip-{theme}-2x.png")
        print("wrote strip", theme, sheet.size)


if __name__ == "__main__":
    main()
