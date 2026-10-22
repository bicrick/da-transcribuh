#!/usr/bin/env python3
"""README hero banner (light): dt mark + wordmark + tagline | transcript/island card.

No trailing block cursor. Departure Mono, 2pt stroke, 3pt hard offset, square edges.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
SYMBOL = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
OUT_BRAND = ROOT / "assets" / "brand"
OUT_ART = Path("/opt/cursor/artifacts")

S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)
W, H = int(920 * S), int(220 * S)


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEPARTURE), size=size)


def font_sym(size: float) -> ImageFont.FreeTypeFont:
    if SYMBOL.exists():
        return ImageFont.truetype(str(SYMBOL), size=size)
    return font(size)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def text_size(d: ImageDraw.ImageDraw, text: str, f: ImageFont.ImageFont) -> tuple[int, int]:
    bb = d.textbbox((0, 0), text, font=f)
    return bb[2] - bb[0], bb[3] - bb[1]


def draw_dt_mark(d: ImageDraw.ImageDraw, x: float, y: float, side: float) -> None:
    """Square plate + hard bevel; Departure d + inverted t block."""
    d.rectangle([x + BEVEL, y + BEVEL, x + side + BEVEL, y + side + BEVEL], fill=(0, 0, 0))
    d.rectangle([x, y, x + side, y + side], fill=(255, 255, 255), outline=(0, 0, 0), width=STROKE)
    f = font(side * 0.42)
    # "d"
    db = d.textbbox((0, 0), "d", font=f)
    dw, dh = db[2] - db[0], db[3] - db[1]
    # "t" in inverted block
    tb = d.textbbox((0, 0), "t", font=f)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    pad_x, pad_y, gap = 5 * S, 4 * S, 4 * S
    bw, bh = tw + pad_x * 2, max(dh, th) + pad_y * 2
    total = dw + gap + bw
    left = x + (side - total) / 2
    top = y + (side - max(dh, bh)) / 2
    d.text((left - db[0], top + (max(dh, bh) - dh) / 2 - db[1]), "d", font=f, fill=(0, 0, 0))
    bx = left + dw + gap
    by = top + (max(dh, bh) - bh) / 2
    d.rectangle([bx, by, bx + bw, by + bh], fill=(0, 0, 0))
    d.text((bx + (bw - tw) / 2 - tb[0], by + (bh - th) / 2 - tb[1]), "t", font=f, fill=(255, 255, 255))


def draw_transcript_card(d: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float) -> None:
    """Recording / transcript card — current island language, no cursors."""
    d.rectangle([x + BEVEL, y + BEVEL, x + w + BEVEL, y + h + BEVEL], fill=(0, 0, 0))
    d.rectangle([x, y, x + w, y + h], fill=(255, 255, 255), outline=(0, 0, 0), width=STROKE)
    # title strip (stipple-ish fill)
    strip = int(18 * S)
    d.rectangle([x, y, x + w, y + strip], fill=(240, 240, 240))
    d.rectangle([x, y + strip - STROKE, x + w, y + strip], fill=(0, 0, 0))
    # tiny record + timer (island cue)
    d.rectangle([x + 10 * S, y + 5 * S, x + 10 * S + 8 * S, y + 5 * S + 8 * S], fill=hex_rgb("#ED1C24"), outline=(0, 0, 0), width=1)
    d.text((x + 24 * S, y + 3 * S), "0:07", font=font(10 * S), fill=(0, 0, 0))
    # body
    by = y + strip + 12 * S
    lines = [
        ("> listenin…", (102, 102, 102)),
        ("ok so the save button", (0, 0, 0)),
        ("should go on the left", (0, 0, 0)),
    ]
    for text, col in lines:
        d.text((x + 12 * S, by), text, font=font(13 * S), fill=col)
        by += 18 * S
    # footer
    fy = y + h - 22 * S
    d.rectangle([x, fy, x + w, fy + 1], fill=(192, 192, 192))
    d.text((x + 12 * S, fy + 5 * S), "0:07 · small.en", font=font(10 * S), fill=(102, 102, 102))
    tw, _ = text_size(d, "copied", font(10 * S))
    d.text((x + w - 12 * S - tw, fy + 5 * S), "copied", font=font(10 * S), fill=(102, 102, 102))


def render() -> Image.Image:
    img = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)

    # Left: mark + wordmark + tagline
    mark = 56 * S
    mx, my = 36 * S, (H - mark) / 2 - 8 * S
    draw_dt_mark(d, mx, my, mark)

    word = "da transcribuh"
    wf = font(28 * S)
    ww, wh = text_size(d, word, wf)
    wx = mx + mark + BEVEL + 18 * S
    wy = my + 4 * S
    d.text((wx, wy), word, font=wf, fill=(0, 0, 0))
    # NO trailing cursor

    tag = "talk. it types. drag if u want the picture too."
    tf = font(12 * S)
    d.text((wx, wy + wh + 10 * S), tag, font=tf, fill=(102, 102, 102))

    # Right: transcript / island card
    card_w, card_h = 300 * S, 140 * S
    cx = W - 36 * S - card_w - BEVEL
    cy = (H - card_h) / 2
    draw_transcript_card(d, cx, cy, card_w, card_h)
    return img


def assert_ok(img: Image.Image) -> None:
    if img.convert("L").getextrema()[0] == img.convert("L").getextrema()[1]:
        raise SystemExit("banner blank")
    # Must contain some white AND dark (not solid black bar)
    hist = img.convert("L").histogram()
    if hist[0] > img.width * img.height * 0.9:
        raise SystemExit("banner mostly black — bad")
    if hist[255] < 100:
        raise SystemExit("banner missing white")
    print(f"ok banner {img.size}")


def main() -> None:
    assert DEPARTURE.exists()
    OUT_BRAND.mkdir(parents=True, exist_ok=True)
    OUT_ART.mkdir(parents=True, exist_ok=True)
    img = render()
    assert_ok(img)
    img.save(OUT_BRAND / "readme-banner.png")
    # also 1× friendly width embed
    img.save(OUT_ART / "readme-banner-2x.png")
    # half-res for github width~920
    small = img.resize((920, int(H / S)), Image.Resampling.LANCZOS)
    small.save(OUT_ART / "readme-banner.png")
    print("wrote assets/brand/readme-banner.png")


if __name__ == "__main__":
    main()
