#!/usr/bin/env python3
"""Composite README.md on a GitHub light page and a GitHub dark page."""

from __future__ import annotations

import re
from pathlib import Path
from typing import NamedTuple

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
SANS = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
MONO = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
OUT = Path("/opt/cursor/artifacts")
OUT_MOCKS = ROOT / "assets" / "brand" / "mocks"

CONTENT = 920
PAD = 48
WINDOW = (0x2C, 0x2C, 0x2E)

RGB = tuple[int, int, int]


def rgb(hex_color: str) -> RGB:
    h = hex_color.removeprefix("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


class Page(NamedTuple):
    slug: str
    bg: RGB
    fg: RGB
    link: RGB
    code_bg: RGB
    border: RGB


LIGHT = Page(
    "github-light",
    rgb("#ffffff"),
    rgb("#1f2328"),
    rgb("#0969da"),
    rgb("#f6f8fa"),
    rgb("#d0d7de"),
)
DARK = Page(
    "github-dark",
    rgb("#0d1117"),
    rgb("#e6edf3"),
    rgb("#4493f8"),
    rgb("#161b22"),
    rgb("#30363d"),
)


class Readme(NamedTuple):
    banner: Path
    demo: Path
    pitch: str
    links: str
    extras: tuple[str, ...]
    lead: str
    commands: tuple[str, ...]
    note: str


def font(path: Path, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def strip_tags(html: str) -> str:
    text = re.sub(r"<[^>]+>", "", html)
    text = text.replace("\u00a0", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def strip_md(text: str) -> str:
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def parse_readme(text: str) -> Readme:
    imgs = re.findall(r'<img[^>]*src="([^"]+)"', text)
    if len(imgs) != 2:
        raise SystemExit(f"README images {imgs}")
    paragraphs = []
    for body in re.findall(r"<p\b[^>]*>(.*?)</p>", text, re.S):
        if "<img" in body:
            continue
        paragraphs.append(strip_tags(body))
    if len(paragraphs) < 4:
        raise SystemExit(f"README paragraphs {paragraphs}")
    pitch, links, *extras = paragraphs
    if "## install" not in text:
        raise SystemExit("README has no install section")
    rest = text.split("## install", 1)[1]
    fence = re.search(r"```[a-zA-Z]*\n(.*?)```", rest, re.S)
    if fence is None:
        raise SystemExit("README has no install commands")
    commands = tuple(line for line in fence.group(1).splitlines() if line.strip())
    lead = strip_md(rest[: fence.start()])
    note = strip_md(rest[fence.end() :])
    if "menu bar" not in pitch:
        raise SystemExit(f"pitch {pitch}")
    if "download" not in links or "macOS 14+" not in links:
        raise SystemExit(f"links {links}")
    if len(extras) != 2 or "⌘" not in extras[1]:
        raise SystemExit(f"extras {extras}")
    if len(commands) != 3 or "WhisperKit" not in note:
        raise SystemExit(f"install {commands} {note}")
    return Readme(
        banner=ROOT / imgs[0],
        demo=ROOT / imgs[1],
        pitch=pitch,
        links=links,
        extras=tuple(extras),
        lead=lead,
        commands=commands,
        note=note,
    )


def lines_for(d: ImageDraw.ImageDraw, text: str, face: ImageFont.ImageFont, width: int) -> list[str]:
    """Keep a paragraph on one line. If it does not fit, break on the sentence."""
    if d.textlength(text, font=face) <= width:
        return [text]
    chunks = text.split(". ")
    if len(chunks) == 1:
        return wrap(d, text, face, width)
    lines: list[str] = []
    for chunk in chunks:
        sentence = chunk if chunk.endswith(".") else f"{chunk}."
        if d.textlength(sentence, font=face) <= width:
            lines.append(sentence)
        else:
            lines.extend(wrap(d, sentence, face, width))
    return lines


def wrap(d: ImageDraw.ImageDraw, text: str, face: ImageFont.ImageFont, width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for word in words:
        trial = word if not cur else f"{cur} {word}"
        if d.textlength(trial, font=face) <= width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def fit(img: Image.Image, width: int) -> Image.Image:
    height = int(img.height * width / img.width)
    return img.resize((width, height), Image.Resampling.LANCZOS)


def text_height(d: ImageDraw.ImageDraw, text: str, face: ImageFont.ImageFont) -> int:
    box = d.textbbox((0, 0), text, font=face)
    return box[3] - box[1]


def render(page: Page, view: Readme, banner: Image.Image, demo: Image.Image) -> Image.Image:
    body = font(SANS, 16)
    link = font(SANS, 16)
    mono = font(MONO, 13)
    h2 = font(SANS, 24)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    pitch_lines = lines_for(probe, view.pitch, body, CONTENT)
    extra_blocks = [lines_for(probe, extra, body, CONTENT) for extra in view.extras]
    lead_lines = lines_for(probe, view.lead, body, CONTENT)
    note_lines = lines_for(probe, view.note, body, CONTENT)
    body_h = text_height(probe, "Ag", body)
    line_gap = body_h + 8
    code_line = 20
    code_h = 16 + len(view.commands) * code_line + 8

    W = CONTENT + PAD * 2
    y = PAD
    banner_y = y
    y += banner.height + 28
    pitch_y = y
    y += len(pitch_lines) * line_gap + 8
    links_y = y
    y += line_gap + 20
    demo_y = y
    y += demo.height + 24
    extras_y = y
    extra_h = sum(len(block) * line_gap for block in extra_blocks)
    extra_h += 6 * (len(extra_blocks) - 1)
    y += extra_h + 28
    install_y = y
    y += 36 + 16
    y += len(lead_lines) * line_gap + 12
    code_y = y
    y += code_h + 16
    note_y = y
    y += len(note_lines) * line_gap + PAD

    img = Image.new("RGB", (W, y), page.bg)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, y - 1], outline=page.border)
    img.paste(banner, ((W - banner.width) // 2, banner_y))
    img.paste(demo, ((W - demo.width) // 2, demo_y))

    def center(lines: list[str], top: int, face: ImageFont.ImageFont, fill: RGB) -> None:
        yy = top
        for line in lines:
            width = d.textlength(line, font=face)
            d.text(((W - width) / 2, yy), line, font=face, fill=fill)
            yy += line_gap

    center(pitch_lines, pitch_y, body, page.fg)
    center([view.links], links_y, link, page.link)
    extra_top = extras_y
    for block in extra_blocks:
        center(block, extra_top, body, page.fg)
        extra_top += len(block) * line_gap + 6

    d.text((PAD, install_y), "install", font=h2, fill=page.fg)
    rule = install_y + 32
    d.line([(PAD, rule), (W - PAD, rule)], fill=page.border, width=1)
    yy = rule + 16
    for line in lead_lines:
        d.text((PAD, yy), line, font=body, fill=page.fg)
        yy += line_gap
    d.rectangle([PAD, code_y, W - PAD, code_y + code_h], fill=page.code_bg, outline=page.border)
    for i, command in enumerate(view.commands):
        d.text((PAD + 16, code_y + 14 + i * code_line), command, font=mono, fill=page.fg)
    for i, line in enumerate(note_lines):
        d.text((PAD, note_y + i * line_gap), line, font=body, fill=page.fg)

    pasted = img.getpixel(((W - banner.width) // 2, banner_y))
    if pasted != WINDOW:
        raise SystemExit(f"{page.slug} banner corner {pasted}")
    if img.getpixel((8, 8)) != page.bg:
        raise SystemExit(f"{page.slug} page background {img.getpixel((8, 8))}")
    return img


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    check = Image.open(path)
    if check.mode != "RGB" or check.size != img.size:
        raise SystemExit(f"{path} saved as {check.mode} {check.size}")


def main() -> None:
    assert SANS.exists(), SANS
    assert MONO.exists(), MONO
    view = parse_readme(README.read_text(encoding="utf-8"))
    assert view.banner.exists(), view.banner
    assert view.demo.exists(), view.demo
    banner = fit(Image.open(view.banner).convert("RGB"), CONTENT)
    demo = fit(Image.open(view.demo).convert("RGB"), CONTENT)
    print("pitch:", view.pitch)
    print("links:", view.links)
    print("extras:", view.extras)
    print("lead:", view.lead)
    print("note:", view.note)
    print("commands:", view.commands)
    for page in (LIGHT, DARK):
        img = render(page, view, banner, demo)
        name = f"readme-preview-{page.slug}.png"
        save(img, OUT / name)
        save(img, OUT_MOCKS / name)
        print("ok", page.slug, img.size)


if __name__ == "__main__":
    main()
