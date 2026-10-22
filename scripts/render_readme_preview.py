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
    extras_h = 22 * 2 + 28  # two extra lines + gap
    y = pad + 8
    by_banner = y
    y += bh + 28
    by_line = y
    y += 20 + 18
    by_links = y
    y += 18 + 28
    by_demo = y
    y += dh + 20
    by_extras = y
    y += extras_h + 28
    by_install = y
    y += 160 + pad

    img = Image.new("RGB", (W, y), (255, 255, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, y - 1], outline=(225, 228, 232))

    img.paste(banner, ((W - bw) // 2, by_banner))

    body = font(SANS, 15)
    link = font(SANS, 14)
    mono = font(MONO, 12)
    h2 = font(SANS, 20)

    line = "free, fast, on-device voice to text in ur menu bar."
    bb = d.textbbox((0, 0), line, font=body)
    d.text(((W - (bb[2] - bb[0])) // 2, by_line), line, font=body, fill=(36, 41, 47))

    links = "download  ·  build from source  ·  MIT  ·  macOS 14+"
    bb = d.textbbox((0, 0), links, font=link)
    d.text(((W - (bb[2] - bb[0])) // 2, by_links), links, font=link, fill=(9, 105, 218))

    img.paste(demo, ((W - dw) // 2, by_demo))

    extras = [
        "if u like that, u'd probably like grabbing screens while u talk. drop a few tiles so u can point at multiple nits in one go.",
        "clipboard history is coming soon (⌘⇧C).",
    ]
    ey = by_extras
    for extra in extras:
        bb = d.textbbox((0, 0), extra, font=body)
        # wrap long first line if needed — keep single line if it fits
        lw = bb[2] - bb[0]
        if lw > W - pad * 2:
            # simple two-line split at "talk. "
            parts = extra.split(". ", 1)
            if len(parts) == 2:
                a, b = parts[0] + ".", parts[1]
                for part in (a, b):
                    bb = d.textbbox((0, 0), part, font=body)
                    d.text(((W - (bb[2] - bb[0])) // 2, ey), part, font=body, fill=(36, 41, 47))
                    ey += 22
                continue
        d.text(((W - lw) // 2, ey), extra, font=body, fill=(36, 41, 47))
        ey += 22

    iy = by_install
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
    for i, c in enumerate(code):
        d.text((pad + 12, cy + i * 16), c, font=mono, fill=(36, 41, 47))
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
