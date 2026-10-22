#!/usr/bin/env python3
"""Render clipboard panel header (title + search) light + dark @2×.

Matches ClipboardHistoryView header: muted lowercase 'clipboard' left,
square search field right (type to search…).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

S = 2.0
STROKE = int(2 * S)
W = int(450 * S)
H = int(40 * S)

LIGHT = {
    "window": "#FFFFFF",
    "fill": "#F0F0F0",
    "label": "#000000",
    "secondary": "#666666",
}
DARK = {
    "window": "#2C2C2E",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
}


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return rgb(pal[key])


def render(pal: dict, name: str) -> Image.Image:
    img = Image.new("RGB", (W, H), c(pal, "fill"))
    d = ImageDraw.Draw(img)
    pad_x = int(12 * S)
    title = "clipboard"
    f = font(11 * S)
    bb = d.textbbox((0, 0), title, font=f)
    th = bb[3] - bb[1]
    d.text((pad_x, (H - th) // 2 - 1), title, font=f, fill=c(pal, "secondary"))

    field_w = int(220 * S)
    field_h = int(23 * S)
    fx = W - pad_x - field_w
    fy = (H - field_h) // 2
    d.rectangle([fx, fy, fx + field_w, fy + field_h], fill=c(pal, "window"), outline=c(pal, "label"), width=STROKE)
    # Drawn glass — Departure Mono has no ⌕ (tofu in dark).
    gx = fx + int(6 * S)
    gy = fy + int(5 * S)
    gs = int(11 * S)
    stroke = max(2, int(1.5 * S))
    glass = gs * 0.62
    d.ellipse([gx, gy, gx + glass, gy + glass], outline=c(pal, "secondary"), width=stroke)
    d.line(
        [gx + glass * 0.72, gy + glass * 0.72, gx + gs - 1, gy + gs - 1],
        fill=c(pal, "secondary"),
        width=stroke,
    )
    placeholder = "type to search…"
    pf = font(12 * S)
    pbb = d.textbbox((0, 0), placeholder, font=pf)
    ph = pbb[3] - pbb[1]
    d.text((fx + int(22 * S), fy + (field_h - ph) // 2 - 1), placeholder, font=pf, fill=c(pal, "secondary"))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    light = render(LIGHT, "light")
    dark = render(DARK, "dark")
    light.save(OUT / "clipboard-header-light-2x.png")
    dark.save(OUT / "clipboard-header-dark-2x.png")
    light.save(OUT_MOCKS / "clipboard-header-light.png")
    dark.save(OUT_MOCKS / "clipboard-header-dark.png")

    gap = 16
    sheet = Image.new("RGB", (W * 2 + gap + 48, H + 80), (90, 90, 90))
    d = ImageDraw.Draw(sheet)
    d.text((24, 16), "clipboard header — light / dark", font=font(14), fill=(242, 242, 242))
    sheet.paste(light, (24, 48))
    sheet.paste(dark, (24 + W + gap, 48))
    sheet.save(OUT / "clipboard-header-strip-2x.png")
    sheet.save(OUT_MOCKS / "clipboard-header-strip.png")
    print("ok", light.size, dark.size)


if __name__ == "__main__":
    main()
