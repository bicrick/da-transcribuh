#!/usr/bin/env python3
"""Clipboard round 2 renders: panel (default/selected/edge preview) + settings tab."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEP = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT = Path("/opt/cursor/artifacts")
MOCKS = ROOT / "assets" / "brand" / "mocks"
S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)

LIGHT = {
    "desk": "#5A5A5A",
    "window": "#FFFFFF",
    "front": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
    "select": "#E6E6E6",
    "hover": "#F0F0F0",
    "bevel": "#000000",
    "hairline": "#C0C0C0",
}
DARK = {
    "desk": "#1A1A1C",
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "select": "#454548",
    "hover": "#3F3F42",
    "bevel": "#F2F2F2",
    "hairline": "#4A4A4E",
}


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEP), size=size)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    h = pal[key].lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def panel(pal: dict, selected: int, preview_left: bool) -> Image.Image:
    pw, ph = int(450 * S), int(480 * S)
    prev_w, prev_h = int(300 * S), int(280 * S)
    gap = int(12 * S)
    W = pw + BEVEL + prev_w + gap + 80
    H = max(ph, prev_h) + BEVEL + 80
    img = Image.new("RGB", (W, H), c(pal, "desk"))
    d = ImageDraw.Draw(img)
    ox = 40 if not preview_left else 40 + prev_w + gap
    oy = 40
    # translucent-ish front: blend front over desk slightly by mixing
    front = tuple(int(a * 0.95 + b * 0.05) for a, b in zip(c(pal, "front"), c(pal, "desk")))
    d.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([ox, oy, ox + pw, oy + ph], fill=front, outline=c(pal, "label"), width=STROKE)
    # header
    hh = int(40 * S)
    d.rectangle([ox, oy, ox + pw, oy + hh], fill=c(pal, "fill"))
    d.text((ox + 12 * S, oy + 12 * S), "clipboard", font=font(11 * S), fill=c(pal, "secondary"))
    fx = ox + pw - 12 * S - 220 * S
    d.rectangle([fx, oy + 8 * S, fx + 220 * S, oy + 31 * S], outline=c(pal, "label"), width=STROKE, fill=c(pal, "window"))
    d.text((fx + 22 * S, oy + 12 * S), "type to search…", font=font(12 * S), fill=c(pal, "secondary"))
    rows = [
        "API_KEY=sk-••••",
        "func paste() { … }",
        "https://github.com/bicrick/da-transcribuh",
        "[image thumb]",
        "meeting notes",
        "island bevel invert",
    ]
    y = oy + hh
    row_h = int(22 * S)
    for i, text in enumerate(rows):
        bg = c(pal, "select") if i == selected else (c(pal, "hover") if i == selected - 1 else front)
        d.rectangle([ox + STROKE, y, ox + pw - 14 * S, y + row_h], fill=bg)
        if text == "[image thumb]":
            d.rectangle([ox + 16 * S, y + 2 * S, ox + 16 * S + 48 * S, y + row_h - 2 * S], outline=c(pal, "hairline"), width=1, fill=c(pal, "fill"))
        else:
            d.text((ox + 16 * S, y + 4 * S), text[:40], font=font(11 * S), fill=c(pal, "label"))
        d.text((ox + pw - 40 * S, y + 5 * S), f"⌘{i+1}", font=font(10 * S), fill=c(pal, "secondary"))
        y += row_h
    # full-height track
    tx = ox + pw - 10 * S - 2 * S
    d.rectangle([tx, oy + hh, tx + 10 * S, oy + ph - 72 * S], outline=c(pal, "label"), width=STROKE, fill=c(pal, "window"))
    d.rectangle([tx, oy + hh + 20 * S, tx + 10 * S, oy + hh + 80 * S], fill=c(pal, "label"))
    # footer
    fy = oy + ph - 72 * S
    d.rectangle([ox, fy, ox + pw, oy + ph], fill=c(pal, "fill"))
    for i, label in enumerate(["Clear", "Preferences…", "Quit"]):
        d.text((ox + 16 * S, fy + 8 * S + i * 18 * S), label, font=font(11 * S), fill=c(pal, "label"))
    # preview window (own plate)
    px = 40 if preview_left else ox + pw + gap
    py = oy + 40
    d.rectangle([px + BEVEL, py + BEVEL, px + prev_w + BEVEL, py + prev_h + BEVEL], fill=c(pal, "bevel"))
    d.rectangle([px, py, px + prev_w, py + prev_h], fill=front, outline=c(pal, "label"), width=STROKE)
    d.text((px + 12 * S, py + 12 * S), rows[selected][:28], font=font(12 * S), fill=c(pal, "label"))
    d.line([px + 12 * S, py + 40 * S, px + prev_w - 12 * S, py + 40 * S], fill=c(pal, "hairline"))
    for i, (k, v) in enumerate([
        ("Application:", "Safari"),
        ("First copy time:", "Oct 22, 2026"),
        ("Last copy time:", "Oct 22, 2026"),
        ("Number of copies:", "3"),
    ]):
        d.text((px + 12 * S, py + 52 * S + i * 22 * S), k, font=font(10 * S), fill=c(pal, "secondary"))
        d.text((px + 130 * S, py + 52 * S + i * 22 * S), v, font=font(10 * S), fill=c(pal, "label"))
    return img


def settings_tab(pal: dict) -> Image.Image:
    W, H = int(720 * S), int(560 * S)
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)
    d.text((32 * S, 24 * S), "Clipboard", font=font(22 * S), fill=c(pal, "label"))
    d.text((32 * S, 56 * S), "History panel, capture, and paste.", font=font(13 * S), fill=c(pal, "secondary"))
    y = 100 * S
    for section, lines in [
        ("General", ["Enable clipboard history", "Open shortcut ⌘⇧C", "Paste automatically", "Paste without formatting"]),
        ("Storage", ["Save files / images / text", "History size 200 · disk usage", "Sort by last copy"]),
        ("Appearance", ["Popup at cursor", "Pin to top", "Image height 40pt", "Preview delay 400ms"]),
        ("Pins / Ignore / Advanced", ["Pinned titles + keys", "Ignored apps + concealed", "Pause · clear on quit"]),
    ]:
        d.rectangle([32 * S, y, W - 32 * S, y + 18 * S + len(lines) * 22 * S], outline=c(pal, "label"), width=STROKE, fill=c(pal, "fill"))
        d.text((44 * S, y + 6 * S), section, font=font(12 * S), fill=c(pal, "label"))
        for i, line in enumerate(lines):
            d.text((52 * S, y + 28 * S + i * 22 * S), "· " + line, font=font(11 * S), fill=c(pal, "secondary"))
        y += 36 * S + len(lines) * 22 * S
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    MOCKS.mkdir(parents=True, exist_ok=True)
    for name, pal in (("light", LIGHT), ("dark", DARK)):
        for state, sel, left in (("default", 0, False), ("selected", 2, False), ("preview-edge", 1, True)):
            img = panel(pal, sel, left)
            img.save(OUT / f"clipboard-r2-{state}-{name}-2x.png")
            img.save(MOCKS / f"clipboard-r2-{state}-{name}.png")
            print("wrote", state, name, img.size)
        st = settings_tab(pal)
        st.save(OUT / f"clipboard-r2-settings-{name}-2x.png")
        st.save(MOCKS / f"clipboard-r2-settings-{name}.png")
        # strip
        a = Image.open(OUT / f"clipboard-r2-default-{name}-2x.png")
        b = Image.open(OUT / f"clipboard-r2-selected-{name}-2x.png")
        cimg = Image.open(OUT / f"clipboard-r2-preview-edge-{name}-2x.png")
        gap = 16
        strip = Image.new("RGB", (a.width + b.width + cimg.width + gap * 2, max(a.height, b.height, cimg.height)), c(pal, "desk"))
        strip.paste(a, (0, 0))
        strip.paste(b, (a.width + gap, 0))
        strip.paste(cimg, (a.width + b.width + gap * 2, 0))
        strip.save(OUT / f"clipboard-r2-strip-{name}-2x.png")
        print("strip", name, strip.size)


if __name__ == "__main__":
    main()
