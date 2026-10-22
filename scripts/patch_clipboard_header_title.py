#!/usr/bin/env python3
"""Replace panel header title 'da transcribuh' → 'clipboard' in ours mocks.

Only patches the header band (y ≈ 40–140), never list-row secondary ink.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEP = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
MOCKS = ROOT / "assets" / "brand" / "mocks"
OUT = Path("/opt/cursor/artifacts")

SINGLE = [
    "clipboard-a-default-light.png",
    "clipboard-a-default-dark.png",
    "clipboard-a-selected-light.png",
    "clipboard-a-selected-dark.png",
    "clipboard-a-search-light.png",
    "clipboard-a-search-dark.png",
    "clipboard-a-preview-image-light.png",
    "clipboard-a-preview-image-dark.png",
    "clipboard-a-preview-text-light.png",
    "clipboard-a-preview-text-dark.png",
]

SHEETS = [
    "clipboard-a-preview-light.png",
    "clipboard-a-preview-dark.png",
    "clipboard-a-states-light.png",
    "clipboard-a-states-dark.png",
]


def font(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEP), size=size)


def ink(arr: np.ndarray, dark: bool) -> np.ndarray:
    gray = arr.mean(axis=2)
    if dark:
        return (gray > 140) & (gray < 200) & (np.abs(arr[:, :, 0].astype(int) - arr[:, :, 1]) < 8)
    return (gray > 90) & (gray < 120) & (np.abs(arr[:, :, 0].astype(int) - arr[:, :, 1]) < 8)


def find_in_band(
    mask: np.ndarray, y_lo: int, y_hi: int, x_lo: int = 40, x_hi: int = 380
) -> tuple[int, int, int, int] | None:
    band = mask[y_lo:y_hi, x_lo:x_hi]
    ys, xs = np.where(band)
    if len(xs) < 200:
        return None
    box = (int(xs.min()) + x_lo, int(ys.min()) + y_lo, int(xs.max()) + x_lo, int(ys.max()) + y_lo)
    if not (170 <= box[2] - box[0] <= 260):
        return None
    return box


def patch_at(im: Image.Image, arr: np.ndarray, box: tuple[int, int, int, int], dark: bool) -> None:
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(im)
    bg = tuple(int(v) for v in arr[max(0, y0 - 2), max(0, x0 - 2)])
    d.rectangle([x0 - 2, y0 - 2, x1 + 2, y1 + 2], fill=bg)
    sec = (0xA8, 0xA8, 0xAD) if dark else (0x66, 0x66, 0x66)
    d.text((x0, y0 - 6), "clipboard", font=font(22), fill=sec)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for name in SINGLE:
        p = MOCKS / name
        im = Image.open(p).convert("RGB")
        arr = np.array(im)
        dark = "dark" in name
        box = find_in_band(ink(arr, dark), 40, 90)
        if not box:
            print("miss", name)
            continue
        print(name, box)
        patch_at(im, arr, box, dark)
        im.save(p)
        im.save(OUT / name.replace(".png", "-2x.png"))
        n += 1

    for name in SHEETS:
        p = MOCKS / name
        im = Image.open(p).convert("RGB")
        arr = np.array(im)
        dark = "dark" in name
        mask = ink(arr, dark)
        hits: list[tuple[int, int, int, int]] = []
        for y_lo, y_hi in ((90, 140), (1400, 1470)):
            for x_lo in range(40, max(41, im.width - 200), 900):
                box = find_in_band(mask, y_lo, y_hi, x_lo, x_lo + 350)
                if box:
                    hits.append(box)
        print(name, hits)
        for box in hits:
            patch_at(im, arr, box, dark)
            n += 1
        if hits:
            im.save(p)
            im.save(OUT / name.replace(".png", "-2x.png"))

    for p in sorted(MOCKS.glob("clipboard-a-compare*.png")):
        im = Image.open(p).convert("RGB")
        arr = np.array(im)
        dark = "dark" in p.name
        mask = ink(arr, dark)
        hits = []
        for y_lo, y_hi in ((70, 130), (1520, 1580)):
            for x_lo in (1000, 1060, 4200, 4300):
                if x_lo >= im.width:
                    continue
                box = find_in_band(mask, y_lo, y_hi, x_lo, min(im.width - 10, x_lo + 350))
                if box:
                    hits.append(box)
        uniq: list[tuple[int, int, int, int]] = []
        for b in hits:
            if not any(abs(b[0] - u[0]) < 20 and abs(b[1] - u[1]) < 20 for u in uniq):
                uniq.append(b)
        print(p.name, uniq)
        for box in uniq:
            patch_at(im, arr, box, dark)
            n += 1
        if uniq:
            im.save(p)
            im.save(OUT / p.name.replace(".png", "-2x.png"))

    print("patched", n)


if __name__ == "__main__":
    main()
