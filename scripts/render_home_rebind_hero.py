#!/usr/bin/env python3
"""Home hero row: ⌥Space keycaps + 'click to rebind' + Start — light/dark @2×.

Verifies output is not blank / not wordmark-only before saving.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
SYMBOL = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)
HAIRLINE = max(1, int(S))

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
}
DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#F2F2F2",
    "primary": "#F2F2F2",
    "on_primary": "#2C2C2E",
    "mark_face": "#3A3A3D",
    "mark_ink": "#F2F2F2",
    "mark_inv_face": "#F2F2F2",
    "mark_inv_ink": "#3A3A3D",
    "control": "#F2F2F2",
}


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return hex_rgb(pal[key])


def font_departure(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def font_symbol(size: float) -> ImageFont.FreeTypeFont:
    if SYMBOL.exists():
        return ImageFont.truetype(str(SYMBOL), size=size)
    return font_departure(size)


def text_size(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = draw.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def font_for_label(label: str, size: float) -> ImageFont.FreeTypeFont:
    if any(ord(ch) > 127 for ch in label):
        return font_symbol(size)
    return font_departure(size)


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, side: float, pal: dict) -> None:
    draw.rectangle([x + BEVEL, y + BEVEL, x + side + BEVEL, y + side + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + side, y + side], fill=c(pal, "mark_face"), outline=c(pal, "control"), width=STROKE)
    f = font_departure(side * 0.38)
    d_bb = draw.textbbox((0, 0), "d", font=f)
    t_bb = draw.textbbox((0, 0), "t", font=f)
    dw, dh = d_bb[2] - d_bb[0], d_bb[3] - d_bb[1]
    tw, th = t_bb[2] - t_bb[0], t_bb[3] - t_bb[1]
    pad_x, pad_y, gap = 4 * S, 3 * S, 3 * S
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = x + (side - total) / 2
    top = y + (side - max(dh, bh)) / 2
    draw.text((left - d_bb[0], top + (max(dh, bh) - dh) / 2 - d_bb[1]), "d", font=f, fill=c(pal, "mark_ink"))
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    draw.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "mark_inv_face"))
    draw.text(
        (bx + (bw - tw) / 2 - t_bb[0], by + (bh - th) / 2 - t_bb[1]),
        "t",
        font=f,
        fill=c(pal, "mark_inv_ink"),
    )


def draw_keycap(draw: ImageDraw.ImageDraw, x: float, y: float, label: str, pal: dict, h: float = 26 * S) -> float:
    f = font_for_label(label, h * 0.42)
    tw, th = text_size(draw, label, f)
    pad = 12 * S if len(label) > 2 else 8 * S
    w = max(h, tw + pad * 2)
    draw.rectangle([x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([x, y, x + w, y + h], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
    draw.text((x + (w - tw) / 2, y + (h - th) / 2), label, font=f, fill=c(pal, "label"))
    return w


def render_hero(pal: dict) -> Image.Image:
    # Wide crop of Home hero: wordmark strip + start row with rebind hint
    W, H = int(900 * S), int(160 * S)
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)
    side = 24 * S
    mx, my = 28 * S, 20 * S

    # Wordmark row (context, but not the only content)
    draw_mark(d, mx, my, 40 * S, pal)
    d.text((mx + 40 * S + 14 * S, my + 8 * S), "da transcribuh", font=font_departure(18 * S), fill=c(pal, "label"))

    # Divider + Start row
    row_y = my + 40 * S + 28 * S
    d.rectangle([side, row_y - 14 * S, W - side, row_y - 14 * S + HAIRLINE], fill=c(pal, "hairline"))

    # Record dot + title
    d.rectangle(
        [side, row_y + 6 * S, side + 10 * S, row_y + 16 * S],
        fill=hex_rgb("#ED1C24"),
        outline=c(pal, "label"),
        width=STROKE,
    )
    d.text((side + 16 * S, row_y + 2 * S), "Start a session", font=font_departure(13 * S), fill=c(pal, "label"))

    # click to rebind + ⌥ Space keycaps + Start (right-aligned cluster)
    hint = "click to rebind"
    hf = font_departure(10 * S)
    hw, hh = text_size(d, hint, hf)
    caps = ["⌥", "Space"]
    # measure keycaps
    cap_ws: list[float] = []
    for lab in caps:
        f = font_for_label(lab, 26 * S * 0.42)
        tw, _ = text_size(d, lab, f)
        pad = 12 * S if len(lab) > 2 else 8 * S
        cap_ws.append(max(26 * S, tw + pad * 2))
    start_w, start_h = 72 * S, 30 * S
    gap = 6 * S
    cluster = hw + 10 * S + sum(cap_ws) + gap * (len(caps) - 1) + 10 * S + start_w + BEVEL
    kx = W - side - cluster

    d.text((kx, row_y + (26 * S - hh) / 2), hint, font=hf, fill=c(pal, "secondary"))
    kx += hw + 10 * S
    for lab, ww in zip(caps, cap_ws):
        draw_keycap(d, kx, row_y, lab, pal)
        kx += ww + gap
    bx, by = kx + 4 * S, row_y - 2 * S
    d.rectangle([bx + BEVEL, by + BEVEL, bx + start_w + BEVEL, by + start_h + BEVEL], fill=hex_rgb("#ED1C24"))
    d.rectangle([bx, by, bx + start_w, by + start_h], fill=c(pal, "primary"), outline=c(pal, "control"), width=STROKE)
    d.rectangle(
        [bx + 10 * S, by + 11 * S, bx + 18 * S, by + 19 * S],
        fill=hex_rgb("#ED1C24"),
        outline=c(pal, "on_primary"),
        width=STROKE,
    )
    d.text((bx + 24 * S, by + 6 * S), "Start", font=font_departure(13 * S), fill=c(pal, "on_primary"))
    return img


def render_zoom(pal: dict) -> Image.Image:
    """Tight crop on hint + keycaps only."""
    W, H = int(420 * S), int(80 * S)
    img = Image.new("RGB", (W, H), c(pal, "window"))
    d = ImageDraw.Draw(img)
    hint = "click to rebind"
    hf = font_departure(11 * S)
    hw, hh = text_size(d, hint, hf)
    y = (H - 28 * S) / 2
    x = 20 * S
    d.text((x, y + (28 * S - hh) / 2), hint, font=hf, fill=c(pal, "secondary"))
    x += hw + 12 * S
    for lab in ("⌥", "Space"):
        w = draw_keycap(d, x, y, lab, pal, h=28 * S)
        x += w + 8 * S
    return img


def assert_usable(img: Image.Image, name: str) -> None:
    """Reject blank or near-empty frames (the failure mode on #19)."""
    extrema = img.convert("L").getextrema()
    if extrema[0] == extrema[1]:
        raise SystemExit(f"FAIL {name}: blank (uniform) image")
    # Sample: must have meaningful dark+light variance for light mocks,
    # or mid-tone variance for dark — at least not a single-color field.
    hist = img.convert("L").histogram()
    nonzero = sum(1 for v in hist if v > 0)
    if nonzero < 8:
        raise SystemExit(f"FAIL {name}: too few distinct tones ({nonzero})")
    w, h = img.size
    if w < 400 or h < 80:
        raise SystemExit(f"FAIL {name}: crop too small {w}x{h}")
    print(f"ok {name}: {w}x{h} tones={nonzero}")


def main() -> None:
    assert DEPARTURE.exists(), DEPARTURE
    assert SYMBOL.exists(), SYMBOL
    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)

    light = render_hero(LIGHT)
    dark = render_hero(DARK)
    assert_usable(light, "hero-light")
    assert_usable(dark, "hero-dark")

    # Side-by-side contact
    gap = 24
    comb = Image.new("RGB", (max(light.width, dark.width), light.height + dark.height + gap), (40, 40, 40))
    comb.paste(light, (0, 0))
    comb.paste(dark, (0, light.height + gap))
    assert_usable(comb, "hero-combined")

    zoom = render_zoom(LIGHT)
    assert_usable(zoom, "zoom-light")
    zoom_d = render_zoom(DARK)
    assert_usable(zoom_d, "zoom-dark")

    light.save(OUT / "home-option-space-rebind-light-2x.png")
    dark.save(OUT / "home-option-space-rebind-dark-2x.png")
    comb.save(OUT / "home-option-space-rebind-2x.png")
    zoom.save(OUT / "home-rebind-hint-zoom-light.png")
    zoom_d.save(OUT / "home-rebind-hint-zoom-dark.png")

    light.save(OUT_MOCKS / "home-option-space-rebind-light.png")
    dark.save(OUT_MOCKS / "home-option-space-rebind-dark.png")
    zoom.save(OUT_MOCKS / "home-rebind-hint-zoom-light.png")

    print("wrote home rebind hero mocks")


if __name__ == "__main__":
    main()
