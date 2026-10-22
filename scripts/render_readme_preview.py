#!/usr/bin/env python3
"""GitHub-like preview of the minimal README (light)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEPARTURE = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
# GitHub body uses system-ish sans; Departure for brand bits only
SANS = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
MONO = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
BANNER = ROOT / "assets" / "brand" / "readme-banner.png"
HOME = ROOT / "assets" / "brand" / "screenshots" / "settings-home-light.png"
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"


def font(path: Path, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def main() -> None:
    assert BANNER.exists(), BANNER
    assert HOME.exists(), HOME
    banner = Image.open(BANNER).convert("RGB")
    # Fit banner to ~860 content width
    bw = 860
    bh = int(banner.height * bw / banner.width)
    banner = banner.resize((bw, bh), Image.Resampling.LANCZOS)
    home = Image.open(HOME).convert("RGB")
    hw = 860
    hh = int(home.height * hw / home.width)
    home = home.resize((hw, hh), Image.Resampling.LANCZOS)

    pad = 48
    W = bw + pad * 2
    # Approximate stack heights
    y = pad
    blocks = []
    # title-ish spacing
    y += 8
    blocks.append(("banner", y, bh))
    y += bh + 28
    blocks.append(("line", y, 20))
    y += 20 + 18
    blocks.append(("links", y, 18))
    y += 18 + 28
    blocks.append(("home", y, hh))
    y += hh + 36
    blocks.append(("install", y, 160))
    y += 160 + pad

    img = Image.new("RGB", (W, y), (255, 255, 255))
    d = ImageDraw.Draw(img)
    # subtle page border like github readme pane
    d.rectangle([0, 0, W - 1, y - 1], outline=(225, 228, 232))

    # banner
    _, by, _ = blocks[0]
    img.paste(banner, ((W - bw) // 2, by))

    body = font(SANS, 15)
    link = font(SANS, 14)
    mono = font(MONO, 12)
    h2 = font(SANS, 20)

    # centered line
    line = "dictation in ur menu bar. grab the screen when u want the picture with the words."
    bb = d.textbbox((0, 0), line, font=body)
    lw = bb[2] - bb[0]
    d.text(((W - lw) // 2, blocks[1][1]), line, font=body, fill=(36, 41, 47))

    # links
    links = "download  ·  build from source  ·  MIT  ·  macOS 14+"
    bb = d.textbbox((0, 0), links, font=link)
    lw = bb[2] - bb[0]
    d.text(((W - lw) // 2, blocks[2][1]), links, font=link, fill=(9, 105, 218))

    # home demo
    img.paste(home, ((W - hw) // 2, blocks[3][1]))

    # install
    iy = blocks[4][1]
    d.text((pad, iy), "install", font=h2, fill=(36, 41, 47))
    d.rectangle([pad, iy + 28, pad + 80, iy + 30], fill=(36, 41, 47))
    body2 = "download da-transcribuh.dmg, open it, drag to applications. done."
    d.text((pad, iy + 40), body2, font=body, fill=(36, 41, 47))
    code = [
        "git clone https://github.com/bicrick/da-transcribuh.git",
        "cd da-transcribuh",
        "open PromptAnnotator.xcodeproj",
    ]
    cy = iy + 72
    d.rectangle([pad, cy - 8, W - pad, cy + 58], fill=(246, 248, 250), outline=(225, 228, 232))
    for i, line in enumerate(code):
        d.text((pad + 12, cy + i * 16), line, font=mono, fill=(36, 41, 47))
    d.text((pad, cy + 70), "macOS 14 or later. the first build fetches WhisperKit.", font=body, fill=(36, 41, 47))

    OUT.mkdir(parents=True, exist_ok=True)
    OUT_MOCKS.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "readme-preview-2x.png")
    img.save(OUT_MOCKS / "readme-preview.png")
    # also half for display
    img.resize((img.width // 2, img.height // 2), Image.Resampling.LANCZOS).save(OUT / "readme-preview.png")
    print("ok preview", img.size)


if __name__ == "__main__":
    main()
