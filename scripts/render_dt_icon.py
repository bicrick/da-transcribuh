#!/usr/bin/env python3
"""Render the chosen da transcribuh mark into AppIcon + brand + menubar assets.

Mark: Departure Mono lowercase "d" + inverted "t" (white on black block).
Container: white square, black hairline, black hard-offset bevel (no squircle).
macOS AppIcon: transparent margin (~100/1024) around the square plate.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
ICONSET = ROOT / "PromptAnnotator" / "Assets.xcassets" / "AppIcon.appiconset"
MENUSET = ROOT / "PromptAnnotator" / "Assets.xcassets" / "MenuBarIcon.imageset"
BRAND = ROOT / "assets" / "brand"


def load_font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), size=size)


def draw_mark(draw: ImageDraw.ImageDraw, cx: float, cy: float, glyph: float, fill_d=(0, 0, 0), fill_t=(255, 255, 255), block=(0, 0, 0)) -> None:
    """Centered d + inverted-t at (cx, cy)."""
    font = load_font(glyph)
    gap = max(1.0, glyph * 0.08)

    d = "d"
    t = "t"
    d_box = draw.textbbox((0, 0), d, font=font)
    t_box = draw.textbbox((0, 0), t, font=font)
    d_w, d_h = d_box[2] - d_box[0], d_box[3] - d_box[1]
    t_w, t_h = t_box[2] - t_box[0], t_box[3] - t_box[1]

    block_pad_x = glyph * 0.14
    block_pad_y = glyph * 0.08
    block_w = t_w + block_pad_x * 2
    block_h = max(d_h, t_h) + block_pad_y * 2

    total_w = d_w + gap + block_w
    total_h = max(d_h, block_h)
    left = cx - total_w / 2
    top = cy - total_h / 2

    # d
    d_x = left - d_box[0]
    d_y = top + (total_h - d_h) / 2 - d_box[1]
    draw.text((d_x, d_y), d, font=font, fill=fill_d)

    # inverted t block
    bx = left + d_w + gap
    by = top + (total_h - block_h) / 2
    draw.rectangle([bx, by, bx + block_w, by + block_h], fill=block)
    t_x = bx + (block_w - t_w) / 2 - t_box[0]
    t_y = by + (block_h - t_h) / 2 - t_box[1]
    draw.text((t_x, t_y), t, font=font, fill=fill_t)


def render_app_icon(size: int) -> Image.Image:
    """Square white plate + black bevel + mark, with macOS transparent margin."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ~100px margin on 1024 canvas (Terminal / Notes footprint)
    inset = size * 100 / 1024
    bevel = max(2.0, size * 0.028)
    # Plate fits inside margin; leave room for bevel so it doesn't clip
    plate = inset
    plate_size = size - inset * 2 - bevel
    x0, y0 = plate, plate
    x1, y1 = x0 + plate_size, y0 + plate_size

    # Black hard offset (down-right)
    draw.rectangle([x0 + bevel, y0 + bevel, x1 + bevel, y1 + bevel], fill=(0, 0, 0, 255))
    # White face
    draw.rectangle([x0, y0, x1, y1], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=max(1, size // 128))

    glyph = plate_size * 0.42
    draw_mark(draw, (x0 + x1) / 2, (y0 + y1) / 2, glyph)
    return img


def render_in_app_tile(size: int) -> Image.Image:
    """Full-bleed white tile + bevel (brand / README icon mark)."""
    bevel = max(2, round(size * 0.06))
    canvas = size + bevel
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rectangle([bevel, bevel, size + bevel - 1, size + bevel - 1], fill=(0, 0, 0, 255))
    draw.rectangle([0, 0, size - 1, size - 1], fill=(255, 255, 255, 255), outline=(0, 0, 0, 255), width=max(1, size // 64))
    draw_mark(draw, size / 2, size / 2, size * 0.46)
    return img


def render_menubar_template(size: int) -> Image.Image:
    """Template (black-on-transparent) d + inverted-t, no container — menubar legibility."""
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(base)
    font = load_font(size * 0.72)
    gap = max(1.0, size * 0.05)
    d_box = bdraw.textbbox((0, 0), "d", font=font)
    t_box = bdraw.textbbox((0, 0), "t", font=font)
    d_w, d_h = d_box[2] - d_box[0], d_box[3] - d_box[1]
    t_w, t_h = t_box[2] - t_box[0], t_box[3] - t_box[1]
    pad_x, pad_y = size * 0.08, size * 0.05
    block_w, block_h = t_w + pad_x * 2, max(d_h, t_h) + pad_y * 2
    total_w = d_w + gap + block_w
    total_h = max(d_h, block_h)
    left, top = size / 2 - total_w / 2, size / 2 - total_h / 2
    bdraw.text((left - d_box[0], top + (total_h - d_h) / 2 - d_box[1]), "d", font=font, fill=(0, 0, 0, 255))
    bx = left + d_w + gap
    by = top + (total_h - block_h) / 2
    bdraw.rectangle([bx, by, bx + block_w, by + block_h], fill=(0, 0, 0, 255))
    # Punch white-on-black t as a transparent hole for template rendering.
    hole = Image.new("L", (size, size), 0)
    hdraw = ImageDraw.Draw(hole)
    hdraw.text(
        (bx + (block_w - t_w) / 2 - t_box[0], by + (block_h - t_h) / 2 - t_box[1]),
        "t",
        font=font,
        fill=255,
    )
    r, g, b, a = base.split()
    a = ImageChops.subtract(a, hole)
    return Image.merge("RGBA", (r, g, b, a))

def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print("wrote", path.relative_to(ROOT), img.size)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-font", action="store_true")
    args = parser.parse_args()
    if not FONT.exists():
        raise SystemExit(f"missing font: {FONT}")
    if args.check_font:
        print("font ok", FONT)
        return

    for size in (16, 32, 64, 128, 256, 512, 1024):
        write_png(render_app_icon(size), ICONSET / f"icon_{size}.png")

    write_png(render_menubar_template(16), MENUSET / "menubar-16.png")
    write_png(render_menubar_template(32), MENUSET / "menubar-32.png")
    write_png(render_menubar_template(16), BRAND / "menubar-g-dt-block-16.png")
    write_png(render_menubar_template(32), BRAND / "menubar-g-dt-block-32.png")

    # Brand mark (full tile with bevel) — replaces squircle icon-g asset
    mark = render_in_app_tile(1024)
    write_png(mark, BRAND / "icon-g-dt-block-1024.png")

    print("done")


if __name__ == "__main__":
    main()
