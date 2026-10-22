#!/usr/bin/env python3
"""GitHub-like preview of the minimal README (light) — island demo."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SANS = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
MONO = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
BANNER = ROOT / "assets" / "brand" / "readme-banner.png"
DEMO = ROOT / "assets" / "brand" / "mocks" / "readme-island-demo-light.png"
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"


def font(path: Path, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def main() -> None:
    assert BANNER.exists(), BANNER
    assert DEMO.exists(), DEMO
    banner = Image.open(BANNER).convert("RGB")
    bw = 860
    bh = int(banner.height * bw / banner.width)
    banner = banner.resize((bw, bh), Image.Resampling.LANCZOS)
    demo = Image.open(DEMO).convert("RGB")
    dw = 860
    dh = int(demo.height * dw / demo.width)
    demo = demo.resize((dw, dh), Image.Resampling.LANCZOS)

    pad = 48
    W = bw + pad * 2
    y = pad + 8
    blocks = []
    blocks.append(("banner", y, bh))
    y += bh + 28
    blocks.append(("line", y, 20))
    y += 20 + 18
    blocks.append(("links", y, 18))
    y += 18 + 28
    blocks.append(("demo", y, dh))
    y += dh + 36
    blocks.append(("install", y, 160))
    y += 160 + pad

    img = Image.new("RGB", (W, y), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, y - 1], outline=(225, 228, 232))

    img.paste(banner, ((W - bw) // 2, blocks[0][1]))

    body = font(SANS, 15)
    link = font(SANS, 14)
    mono = font(MONO, 12)
    h2 = font(SANS, 20)

    line = "dictation in ur menu bar. grab the screen when u want the picture with the words."
    bb = d.textbbox((0, 0), line, font=body)
    lw = bb[2] - bb[0]
    d.text(((W - lw) // 2, blocks[1][1]), line, font=body, fill=(36, 41, 47))

    links = "download  ·  build from source  ·  MIT  ·  macOS 14+"
    bb = d.textbbox((0, 0), links, font=link)
    lw = bb[2] - bb[0]
    d.text(((W - lw) // 2, blocks[2][1]), links, font=link, fill=(9, 105, 218))

    img.paste(demo, ((W - dw) // 2, blocks[3][1]))

    iy = blocks[4][1]
    d.text((pad, iy), "install", font=h2, fill=(36, 41, 47))
    d.rectangle([pad, iy + 28, pad + 80, iy + 30], fill=(36, 41, 47))
    d.text(
        (pad, iy + 40),
        "download da-transcribuh.dmg, open it, drag to applications. done.",
        font=body,
        fill=(36, 41, 47),
    )
    code = [
        "git clone https://github.com/bicrick/da-transcribuh.git",
        "cd da-transcribuh",
        "open PromptAnnotator.xcodeproj",
    ]
    cy = iy + 72
    d.rectangle([pad, cy - 8, W - pad, cy + 58], fill=(246, 248, 250), outline=(225, 228, 232))
    for i, line in enumerate(code):
        d.text((pad + 12, cy + i * 16), line, font=mono, fill=(36, 41, 47))
    d.text(
        (pad, cy + 70),
        "macOS 14 or later. the first build fetches WhisperKit.",
        font=body,
        fill=(36, 41, 47),
    )

    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "readme-preview-island-2x.png")
    img.save(OUT_MOCKS / "readme-preview.png")
    img.resize((img.width // 2, img.height // 2), Image.Resampling.LANCZOS).save(
        OUT / "readme-preview-island.png"
    )
    print("ok preview", img.size)


if __name__ == "__main__":
    main()
