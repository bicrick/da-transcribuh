#!/usr/bin/env python3
"""Render clipboard history panel + onboarding step contact sheets (light + dark @2×)."""

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
    "label": "#000000",
    "secondary": "#666666",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "desk": "#5A5A5A",
}
DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#F2F2F2",
    "desk": "#1A1A1C",
}


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


def draw_panel(pal: dict) -> Image.Image:
    """Clipboard history floating panel with double-pane bevel."""
    pw, ph = int(360 * S), int(420 * S)
    canvas = Image.new("RGB", (pw + BEVEL + 40, ph + BEVEL + 80), c(pal, "desk"))
    d = ImageDraw.Draw(canvas)
    ox, oy = 20, 20
    # Bevel
    d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    # Search
    d.rectangle([ox, oy, ox + pw, oy + 36 * S], fill=c(pal, "fill"))
    d.text((ox + 12 * S, oy + 10 * S), "⌕  Filter…", font=font(12 * S), fill=c(pal, "secondary"))
    d.rectangle([ox, oy + 36 * S, ox + pw, oy + 36 * S + STROKE], fill=c(pal, "label"))
    rows = [
        ("⌘1", "T", "meeting notes — q3 roadmap…", "words"),
        ("⌘2", "img", "Screenshot", "tile"),
        ("⌘3", "T", "https://example.com/spec", ""),
        ("⌘4", "T", "⌥Space starts and stops", ""),
    ]
    y = oy + 36 * S + STROKE
    for i, (digit, kind, preview, tag) in enumerate(rows):
        h = 40 * S
        bg = c(pal, "fill") if i == 0 else c(pal, "front")
        d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + h], fill=bg)
        if i == 0:
            d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + h], outline=c(pal, "label"), width=STROKE)
        d.text((ox + 10 * S, y + 12 * S), digit, font=font(10 * S), fill=c(pal, "secondary"))
        d.rectangle([ox + 48 * S, y + 6 * S, ox + 76 * S, y + 34 * S], outline=c(pal, "label"), width=1)
        d.text((ox + 54 * S, y + 10 * S), kind[:1].upper(), font=font(11 * S), fill=c(pal, "label"))
        d.text((ox + 84 * S, y + 12 * S), preview[:34], font=font(12 * S), fill=c(pal, "label"))
        if tag:
            tw, _ = text_size(d, tag, font(9 * S))
            d.text((ox + pw - 12 * S - tw, y + 14 * S), tag, font=font(9 * S), fill=c(pal, "secondary"))
        y += h
        d.rectangle([ox + STROKE, y, ox + pw - STROKE, y + 1], fill=c(pal, "hairline"))
    # Footer
    fy = oy + ph - 28 * S
    d.rectangle([ox, fy, ox + pw, oy + ph], fill=c(pal, "fill"))
    d.text(
        (ox + 10 * S, fy + 8 * S),
        "↑↓ Enter · ⌥Enter copy · ⌥P pin · Esc",
        font=font(9 * S),
        fill=c(pal, "secondary"),
    )
    cap = "clipboard history · ⌘⇧C · double-pane"
    cw, _ = text_size(d, cap, font(11 * S))
    d.text(((canvas.width - cw) / 2, canvas.height - 36), cap, font=font(11 * S), fill=(180, 180, 180))
    return canvas


def draw_onboarding_step(pal: dict, title: str, body_lines: list[str], rail_idx: int) -> Image.Image:
    w, h = int(560 * S), int(420 * S)
    img = Image.new("RGB", (w, h), c(pal, "window"))
    d = ImageDraw.Draw(img)
    # Title strip
    d.rectangle([0, 0, w, 40 * S], fill=c(pal, "window"))
    tw, th = text_size(d, "da transcribuh", font(13 * S))
    d.text(((w - tw) / 2, (40 * S - th) / 2), "da transcribuh", font=font(13 * S), fill=c(pal, "label"))
    d.rectangle([0, 40 * S - STROKE, w, 40 * S], fill=c(pal, "label"))
    # Rail
    labels = ["Hi", "Perm", "Rec", "Clip", "Look", "Model", "Try", "Go"]
    x = 36 * S
    y = 56 * S
    for i, lab in enumerate(labels):
        col = c(pal, "label") if i == rail_idx else c(pal, "secondary")
        d.text((x, y), lab, font=font(10 * S), fill=col)
        lw, _ = text_size(d, lab, font(10 * S))
        if i == rail_idx:
            d.rectangle([x, y + 16 * S, x + lw, y + 16 * S + STROKE], fill=c(pal, "label"))
        x += lw + 14 * S
    d.text((36 * S, 90 * S), title, font=font(18 * S), fill=c(pal, "label"))
    by = 130 * S
    for line in body_lines:
        d.text((36 * S, by), line, font=font(12 * S), fill=c(pal, "secondary"))
        by += 22 * S
    # Fake card
    d.rectangle(
        [36 * S, by + 8 * S, w - 36 * S, by + 8 * S + 80 * S],
        fill=c(pal, "front"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    d.rectangle(
        [36 * S + BEVEL, by + 8 * S + BEVEL, w - 36 * S + BEVEL, by + 8 * S + 80 * S + BEVEL],
        fill=c(pal, "bevel"),
    )
    # redraw face on top of bevel
    d.rectangle(
        [36 * S, by + 8 * S, w - 36 * S, by + 8 * S + 80 * S],
        fill=c(pal, "front"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    return img


STEPS = [
    ("Welcome", ["Talk + capture tiles.", "Free and open source."], 0),
    ("Permissions", ["Mic · Screen · Accessibility", "Accessibility also covers paste + clipboard."], 1),
    ("Recording shortcut", ["Default ⌥Space · click to rebind", "⌘Space / ⌥⌘Space stay reserved."], 2),
    ("Clipboard history", ["Default ⌘⇧C · enable toggle", "Shares Accessibility — no re-ask."], 3),
    ("Appearance", ["System / Light / Graphite dark", "Same Appearance segment as Settings."], 4),
    ("Model", ["Download English speech model", "Same picker as Models tab."], 5),
    ("Try a session", ["5-second practice take", "Or skip and try from Home."], 6),
    ("Ready", ["⌥Space record · ⌘⇧C clipboard", "Tabs: Home Appearance History…"], 7),
]


def contact_sheet(pal: dict) -> Image.Image:
    cells = [draw_onboarding_step(pal, t, b, i) for t, b, i in STEPS]
    cols = 4
    rows = 2
    cw, ch = cells[0].size
    gap = 16
    sheet = Image.new("RGB", (cols * cw + (cols + 1) * gap, rows * ch + (rows + 1) * gap + 40), c(pal, "desk"))
    d = ImageDraw.Draw(sheet)
    label = "onboarding · light" if pal is LIGHT else "onboarding · dark graphite"
    d.text((gap, 10), label, font=font(14), fill=(200, 200, 200) if pal is DARK else (40, 40, 40))
    for i, cell in enumerate(cells):
        r, cidx = divmod(i, cols)
        x = gap + cidx * (cw + gap)
        y = 40 + gap + r * (ch + gap)
        sheet.paste(cell, (x, y))
    return sheet


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    for name, pal in (("light", LIGHT), ("dark", DARK)):
        panel = draw_panel(pal)
        panel.save(OUT / f"clipboard-panel-{name}-2x.png")
        panel.save(OUT_MOCKS / f"clipboard-panel-{name}.png")
        sheet = contact_sheet(pal)
        sheet.save(OUT / f"onboarding-steps-{name}-2x.png")
        sheet.save(OUT_MOCKS / f"onboarding-steps-{name}.png")
        print("wrote", name)
    # Combined strip
    pl = Image.open(OUT / "clipboard-panel-light-2x.png")
    pd = Image.open(OUT / "clipboard-panel-dark-2x.png")
    gap = 24
    comb = Image.new("RGB", (pl.width + pd.width + gap, max(pl.height, pd.height)), (30, 30, 30))
    comb.paste(pl, (0, 0))
    comb.paste(pd, (pl.width + gap, 0))
    comb.save(OUT / "clipboard-panel-light-dark-2x.png")
    print("done")


if __name__ == "__main__":
    main()
