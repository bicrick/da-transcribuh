#!/usr/bin/env python3
"""Clipboard round 2b renders from the real Settings / panel layout.

Settings is the Clipboard tab (toggles, keycaps, stepper, radios, slider),
light + dark, 2×, full content height — section cards grow with their rows.

Departure Mono for chrome. Caption/body uses DejaVu (stand-in for SF Mono,
which has ⇧/⌘). Keycap ⇧ / ⌫ are the same stroke glyphs as InkMissingGlyphView
because Departure Mono lacks those scalars.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
DEP = ROOT / "PromptAnnotator" / "Fonts" / "DepartureMono-Regular.otf"
SYMBOL = Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
OUT = Path("/opt/cursor/artifacts")
MOCKS = ROOT / "assets" / "brand" / "mocks"
S = 2.0
STROKE = int(2 * S)
BEVEL = int(3 * S)
HAIR = max(1, int(S))

LIGHT = {
    "window": "#FFFFFF",
    "front": "#FFFFFF",
    "fill": "#F0F0F0",
    "card": "#FFFFFF",
    "label": "#000000",
    "secondary": "#666666",
    "hairline": "#C0C0C0",
    "bevel": "#000000",
    "primary": "#000000",
    "on_primary": "#FFFFFF",
    "control": "#000000",
    "select": "#E6E6E6",
    "hover": "#F0F0F0",
    "desk": "#5A5A5A",
    "screen": "#D9D9D9",
}
DARK = {
    "window": "#2C2C2E",
    "front": "#3A3A3D",
    "fill": "#353538",
    "card": "#353538",
    "label": "#F2F2F2",
    "secondary": "#A8A8AD",
    "hairline": "#4A4A4E",
    "bevel": "#F2F2F2",
    "primary": "#F2F2F2",
    "on_primary": "#2C2C2E",
    "control": "#F2F2F2",
    "select": "#454548",
    "hover": "#3F3F42",
    "desk": "#1A1A1C",
    "screen": "#3A3A3D",
}

TABS = [
    ("Home", "#ED1C24", False),
    ("Appearance", "#A349A4", False),
    ("History", "#3F48CC", False),
    ("Clipboard", "#22B14C", True),
    ("Models", "#FF7F27", False),
    ("General", "#008080", False),
    ("Sound", "#FFAEC9", False),
    ("Perf", "#3F48CC", False),
]
DARK_ACCENT = {
    "#ED1C24": "#FF5A5F",
    "#A349A4": "#C46BC5",
    "#3F48CC": "#6B73E0",
    "#FF7F27": "#FF9A4D",
    "#22B14C": "#3FD06A",
    "#008080": "#2AA8A8",
    "#FFAEC9": "#FFC0D6",
}


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def c(pal: dict, key: str) -> tuple[int, int, int]:
    return rgb(pal[key])


def font_dep(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(DEP), size=size)


def font_body(size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(SYMBOL), size=size)


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.ImageFont) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def draw_text(draw: ImageDraw.ImageDraw, xy: tuple[float, float], text: str, fnt, fill) -> None:
    box = draw.textbbox((0, 0), text, font=fnt)
    draw.text((xy[0] - box[0], xy[1] - box[1]), text, font=fnt, fill=fill)


def accent(hex_color: str, pal: dict) -> tuple[int, int, int]:
    if pal is DARK:
        hex_color = DARK_ACCENT.get(hex_color, hex_color)
    return rgb(hex_color)


def draw_shift(draw: ImageDraw.ImageDraw, x: float, y: float, size: float, fill) -> None:
    """Hollow up-arrow matching InkMissingGlyphView.shift."""
    stroke = max(2, int(size * 0.14))
    mid = x + size / 2
    head = y + size * 0.46
    stem = size * 0.16
    pts = [
        (mid, y + stroke),
        (x + size - stroke, head),
        (mid + stem, head),
        (mid + stem, y + size - stroke),
        (mid - stem, y + size - stroke),
        (mid - stem, head),
        (x + stroke, head),
    ]
    draw.line(pts + [pts[0]], fill=fill, width=stroke, joint="miter")


def draw_delete(draw: ImageDraw.ImageDraw, x: float, y: float, size: float, fill) -> None:
    stroke = max(2, int(size * 0.14))
    mid_y = y + size * 0.52
    draw.line([(x + size - stroke, mid_y), (x + size * 0.42, mid_y)], fill=fill, width=stroke)
    draw.line(
        [
            (x + size * 0.55, y + size * 0.28),
            (x + stroke * 1.4, mid_y),
            (x + size * 0.55, y + size * 0.76),
        ],
        fill=fill,
        width=stroke,
        joint="miter",
    )


class Sheet:
    def __init__(self, width: int, pal: dict):
        self.width = width
        self.pal = pal
        self.blocks: list[tuple[int, object]] = []
        self.height = 0

    def add(self, height: int, painter) -> None:
        self.blocks.append((self.height, painter))
        self.height += height

    def render(self, background: str) -> Image.Image:
        img = Image.new("RGB", (self.width, max(1, self.height)), c(self.pal, background))
        draw = ImageDraw.Draw(img)
        for y, painter in self.blocks:
            painter(draw, y)
        return img


def paint_settings(pal: dict) -> Image.Image:
    win = int(1040 * S)
    sheet = Sheet(win, pal)
    content_w = int(920 * S)
    content_x = (win - content_w) // 2
    inner_x = content_x + int(36 * S)
    inner_w = content_w - int(72 * S)

    def title_strip(draw: ImageDraw.ImageDraw, y: int) -> None:
        h = int(40 * S)
        draw.rectangle([0, y, win, y + h], fill=c(pal, "window"))
        draw.rectangle([0, y + h - HAIR, win, y + h], fill=c(pal, "label"))
        for i, col in enumerate(["#ED1C24", "#FFF200", "#22B14C"]):
            x = int(12 * S) + i * int(18 * S)
            draw.rectangle(
                [x, y + int(12 * S), x + int(11 * S), y + int(23 * S)],
                fill=rgb(col),
                outline=c(pal, "label"),
                width=STROKE,
            )
        fnt = font_dep(13 * S)
        label = "da transcribuh"
        tw, th = text_size(draw, label, fnt)
        draw_text(draw, ((win - tw) / 2, y + (h - th) / 2), label, fnt, c(pal, "label"))

    sheet.add(int(40 * S), title_strip)

    def tabs(draw: ImageDraw.ImageDraw, y: int) -> None:
        shelf_h = int((8 + 30) * S)
        tab_h = int(30 * S)
        tab_bottom = y + shelf_h
        draw.rectangle([0, y, win, tab_bottom - STROKE], fill=c(pal, "fill"))
        draw.rectangle([0, tab_bottom - STROKE, win, sheet.height], fill=c(pal, "front"))
        fnt = font_dep(11 * S)
        x = int(36 * S)
        placed = []
        for name, color, selected in TABS:
            tw, _ = text_size(draw, name, fnt)
            face = int(10 * S + 5 * S + tw + 24 * S)
            placed.append((x, name, color, selected, face))
            x += face + int(6 * S)
        for x0, name, color, selected, face in placed:
            if selected:
                continue
            top = tab_bottom - tab_h
            draw.polygon(
                [(x0, tab_bottom), (x0, top), (x0 + face, top), (x0 + face, tab_bottom)],
                fill=c(pal, "fill"),
            )
            draw.line(
                [(x0, tab_bottom), (x0, top), (x0 + face, top), (x0 + face, tab_bottom)],
                fill=accent(color, pal),
                width=STROKE,
                joint="miter",
            )
            tw, th = text_size(draw, name, fnt)
            draw_text(draw, (x0 + (face - tw) / 2, top + (tab_h - th) / 2), name, fnt, c(pal, "secondary"))
        sel = next(item for item in placed if item[3])
        x0, name, color, _, face = sel
        top = tab_bottom - tab_h
        draw.polygon(
            [(x0, tab_bottom), (x0, top), (x0 + face, top), (x0 + face, tab_bottom)],
            fill=c(pal, "front"),
        )
        tw, th = text_size(draw, name, fnt)
        draw_text(draw, (x0 + (face - tw) / 2, top + (tab_h - th) / 2), name, fnt, c(pal, "label"))
        shelf_y = tab_bottom - STROKE / 2
        top_line = top + STROKE / 2
        draw.line(
            [
                (0, shelf_y),
                (x0, shelf_y),
                (x0, top_line),
                (x0 + face, top_line),
                (x0 + face, shelf_y),
                (win, shelf_y),
            ],
            fill=accent(color, pal),
            width=STROKE,
            joint="miter",
        )
        chip = "⌘K"
        cf = font_body(10 * S)
        cw, ch = text_size(draw, chip, cf)
        chip_w, chip_h = cw + int(16 * S), int(18 * S)
        chip_x = win - int(36 * S) - chip_w
        band_top = y
        band_bottom = tab_bottom - STROKE
        chip_y = band_top + (band_bottom - band_top - chip_h) / 2
        draw.rectangle(
            [chip_x, chip_y, chip_x + chip_w, chip_y + chip_h],
            fill=c(pal, "fill"),
            outline=c(pal, "control"),
            width=STROKE,
        )
        draw_text(draw, (chip_x + int(8 * S), chip_y + (chip_h - ch) / 2), chip, cf, c(pal, "secondary"))

    sheet.add(int(38 * S), tabs)

    def header(draw: ImageDraw.ImageDraw, y: int) -> None:
        title_f = font_dep(22 * S)
        sub_f = font_body(13 * S)
        top = y + int(28 * S)
        draw_text(draw, (inner_x, top), "Clipboard", title_f, c(pal, "label"))
        _, th = text_size(draw, "Clipboard", title_f)
        sub = "History panel, capture, and paste — Maccy-shaped, Paint chrome."
        draw_text(draw, (inner_x, top + th + int(8 * S)), sub, sub_f, c(pal, "secondary"))

    title_h = text_size(ImageDraw.Draw(Image.new("RGB", (1, 1))), "Clipboard", font_dep(22 * S))[1]
    sub_h = text_size(ImageDraw.Draw(Image.new("RGB", (1, 1))), "x", font_body(13 * S))[1]
    sheet.add(int(28 * S) + title_h + int(8 * S) + sub_h, header)

    rows = build_rows(pal)
    y_cursor = sheet.height + int(32 * S)
    # Draw sections directly onto a tall image after measuring.
    measured = measure_sections(rows, inner_w)
    body_h = int(32 * S) + measured + int(36 * S)
    # Rebuild with known total: title already added; append body painter.
    def body(draw: ImageDraw.ImageDraw, y: int) -> None:
        draw_sections(draw, pal, rows, inner_x, y + int(32 * S), inner_w)

    sheet.add(body_h, body)

    def status(draw: ImageDraw.ImageDraw, y: int) -> None:
        h = int(32 * S)
        draw.rectangle([0, y, win, y + h], fill=c(pal, "window"))
        draw.rectangle([0, y, win, y + STROKE], fill=c(pal, "label"))
        fnt = font_dep(11 * S)
        draw.rectangle(
            [int(12 * S), y + (h - int(7 * S)) / 2, int(12 * S) + int(7 * S), y + (h + int(7 * S)) / 2],
            fill=c(pal, "label"),
            outline=c(pal, "label"),
            width=max(1, STROKE // 2),
        )
        draw_text(draw, (int(28 * S), y + int(8 * S)), "ready", fnt, c(pal, "label"))
        ver = "1.0"
        vw, _ = text_size(draw, ver, fnt)
        draw_text(draw, (win - int(16 * S) - vw, y + int(8 * S)), ver, fnt, c(pal, "secondary"))

    sheet.add(int(32 * S), status)
    img = sheet.render("front")
    # The tab painter fills downward using sheet.height before status is added.
    # Repaint the page front only behind the body so the status stays window-colored.
    return img


def row_height(detail: bool) -> int:
    title = int(16 * S)
    cap = int(14 * S) if detail else 0
    gap = int(8 * S) if detail else 0
    return int(12 * S) * 2 + title + gap + cap


def build_rows(pal: dict) -> list[dict]:
    del pal
    return [
        {"section": "General", "footer": None, "rows": [
            {"kind": "toggle", "title": "Enable clipboard history", "detail": "⌘⇧C opens the panel.", "on": True},
            {"kind": "divider"},
            {"kind": "shortcut", "title": "Open shortcut", "detail": "Default ⌘⇧C. Shift is allowed for clipboard.", "keys": ["⌘", "⇧", "C"]},
            {"kind": "reset"},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Paste automatically", "detail": "Selecting a row pastes into the frontmost app.", "on": True},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Paste without formatting", "detail": "Stage plain text when pasting history text.", "on": False},
        ]},
        {"section": "Storage", "footer": None, "rows": [
            {"kind": "toggle", "title": "Save files", "detail": "Capture file URLs from the pasteboard.", "on": True},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Save images", "detail": "Capture image pasteboard types.", "on": True},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Save text", "detail": "Capture plain text and RTF as text.", "on": True},
            {"kind": "divider"},
            {"kind": "stepper", "title": "History size", "detail": "On disk: 128 KB", "value": "200"},
            {"kind": "divider"},
            {"kind": "radios", "title": "Sort by", "options": ["Time of last copy", "Time of first copy", "Number of copies"], "selected": 0},
        ]},
        {"section": "Appearance", "footer": None, "rows": [
            {"kind": "radios", "title": "Popup position", "options": ["At cursor", "Near menu bar icon", "Screen center"], "selected": 0},
            {"kind": "divider"},
            {"kind": "radios", "title": "Pinned section", "options": ["Pin to top", "Pin to bottom"], "selected": 0},
            {"kind": "divider"},
            {"kind": "slider", "title": "Image height", "detail": "List thumbnail max height.", "value": "40pt", "fraction": (40 - 24) / (120 - 24)},
            {"kind": "divider"},
            {"kind": "stepper", "title": "Preview delay", "detail": "Hover / selection preview wait.", "value": "400 ms"},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Show search field", "detail": "Header search above the list.", "on": True},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Show footer", "detail": "Clear / Preferences… / Quit.", "on": True},
        ]},
        {"section": "Pins", "footer": "Pin from the panel with ⌥P, then edit titles here.", "rows": [
            {"kind": "note", "text": "No pinned items yet."},
        ]},
        {"section": "Ignore", "footer": None, "rows": [
            {"kind": "toggle", "title": "Ignore concealed and password types", "detail": "Skip transient / confidential pasteboard marks.", "on": True},
            {"kind": "divider"},
            {"kind": "ignore"},
        ]},
        {"section": "Advanced", "footer": None, "rows": [
            {"kind": "toggle", "title": "Pause capture", "detail": "Keep history; stop watching the pasteboard.", "on": False},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Clear history on quit", "detail": "Wipe stored items when the app exits.", "on": False},
            {"kind": "divider"},
            {"kind": "toggle", "title": "Also clear system clipboard", "detail": "When clearing history, empty the general pasteboard.", "on": False},
            {"kind": "divider"},
            {"kind": "button", "label": "Clear history…"},
        ]},
    ]


def section_block_height(section: dict, width: int) -> int:
    header = int(14 * S)
    if section["footer"]:
        header += int(8 * S) + int(14 * S)
    card = sum(row_block_height(row, width) for row in section["rows"])
    return header + int(12 * S) + card


def row_block_height(row: dict, width: int) -> int:
    kind = row["kind"]
    if kind == "divider":
        return HAIR
    if kind == "toggle":
        return row_height(True)
    if kind == "shortcut":
        return row_height(True)
    if kind == "reset":
        return int(12 * S) + int(24 * S) + int(12 * S)
    if kind == "stepper":
        return row_height(True)
    if kind == "slider":
        return row_height(True)
    if kind == "radios":
        return int(12 * S) + int(16 * S) + int(8 * S) + len(row["options"]) * int(22 * S) + int(12 * S)
    if kind == "note":
        return int(12 * S) * 2 + int(14 * S)
    if kind == "ignore":
        return int(12 * S) + int(16 * S) + int(8 * S) + int(28 * S) + int(12 * S)
    if kind == "button":
        return int(12 * S) * 2 + int(24 * S)
    return int(40 * S)


def measure_sections(sections: list[dict], width: int) -> int:
    total = 0
    for index, section in enumerate(sections):
        total += section_block_height(section, width)
        if index < len(sections) - 1:
            total += int(32 * S)
    return total


def draw_sections(draw: ImageDraw.ImageDraw, pal: dict, sections: list[dict], x: int, y: int, width: int) -> int:
    for index, section in enumerate(sections):
        y = draw_section(draw, pal, section, x, y, width)
        if index < len(sections) - 1:
            y += int(32 * S)
    return y


def draw_section(draw: ImageDraw.ImageDraw, pal: dict, section: dict, x: int, y: int, width: int) -> int:
    fnt = font_dep(11 * S)
    title = section["section"].upper()
    tw, th = text_size(draw, title, fnt)
    draw_text(draw, (x, y), title, fnt, c(pal, "label"))
    rule_y = y + th / 2
    draw.rectangle([x + tw + int(8 * S), rule_y, x + width, rule_y + HAIR], fill=c(pal, "label"))
    y += th
    if section["footer"]:
        y += int(8 * S)
        ff = font_body(11 * S)
        draw_text(draw, (x, y), section["footer"], ff, c(pal, "secondary"))
        y += text_size(draw, section["footer"], ff)[1]
    y += int(12 * S)
    card_top = y
    card_h = sum(row_block_height(row, width) for row in section["rows"])
    draw.rectangle([x, card_top, x + width, card_top + card_h], fill=c(pal, "card"))
    cursor = card_top
    for row in section["rows"]:
        cursor = draw_row(draw, pal, row, x, cursor, width)
    # Outline sits on the card edge. Last-row padding stays inside the stroke.
    assert cursor == card_top + card_h, (section["section"], cursor, card_top + card_h)
    inset = STROKE // 2 + 2
    assert cursor - card_top > inset, section["section"]
    draw.rectangle([x, card_top, x + width, cursor], outline=c(pal, "label"), width=STROKE)
    return cursor


def draw_row(draw: ImageDraw.ImageDraw, pal: dict, row: dict, x: int, y: int, width: int) -> int:
    kind = row["kind"]
    pad = int(16 * S)
    if kind == "divider":
        draw.rectangle([x, y, x + width, y + HAIR], fill=c(pal, "hairline"))
        return y + HAIR
    if kind == "toggle":
        h = row_height(True)
        draw_title_detail(draw, pal, row["title"], row["detail"], x + pad, y + int(12 * S), width - int(80 * S))
        draw_switch(draw, pal, x + width - pad - int(34 * S), y + (h - int(18 * S)) / 2, row["on"])
        return y + h
    if kind == "shortcut":
        h = row_height(True)
        draw_title_detail(draw, pal, row["title"], row["detail"], x + pad, y + int(12 * S), width - int(180 * S))
        draw_keycaps(draw, pal, row["keys"], x + width - pad - keycaps_width(draw, row["keys"]), y + (h - int(26 * S)) / 2)
        return y + h
    if kind == "reset":
        h = row_block_height(row, width)
        label = "Reset to ⌘⇧C"
        bw = mixed_width(draw, label, 11 * S) + int(24 * S)
        bh = int(24 * S)
        bx = x + width - pad - bw
        by = y + int(12 * S)
        draw.rectangle([bx, by + BEVEL, bx + bw, by + bh + BEVEL], fill=c(pal, "bevel"))
        draw.rectangle([bx, by, bx + bw, by + bh], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
        draw_mixed(draw, (bx + int(12 * S), by + int(5 * S)), label, 11 * S, c(pal, "label"))
        return y + h
    if kind in {"stepper", "slider"}:
        h = row_height(True)
        draw_title_detail(draw, pal, row["title"], row["detail"], x + pad, y + int(12 * S), width - int(220 * S))
        if kind == "stepper":
            draw_stepper(draw, pal, row["value"], x + width - pad - int(120 * S), y + (h - int(22 * S)) / 2)
        else:
            draw_slider(draw, pal, row["fraction"], row["value"], x + width - pad - int(180 * S), y + (h - int(16 * S)) / 2)
        return y + h
    if kind == "radios":
        h = row_block_height(row, width)
        fnt = font_dep(13 * S)
        draw_text(draw, (x + pad, y + int(12 * S)), row["title"], fnt, c(pal, "label"))
        _, th = text_size(draw, row["title"], fnt)
        opt_y = y + int(12 * S) + th + int(8 * S)
        of = font_body(12 * S)
        for i, option in enumerate(row["options"]):
            draw_radio(draw, pal, x + pad, opt_y + int(3 * S), i == row["selected"])
            draw_text(draw, (x + pad + int(20 * S), opt_y), option, of, c(pal, "label"))
            opt_y += int(22 * S)
        return y + h
    if kind == "note":
        h = row_block_height(row, width)
        draw_text(draw, (x + pad, y + int(12 * S)), row["text"], font_body(11 * S), c(pal, "secondary"))
        return y + h
    if kind == "ignore":
        h = row_block_height(row, width)
        fnt = font_dep(13 * S)
        draw_text(draw, (x + pad, y + int(12 * S)), "Ignored apps (bundle IDs)", fnt, c(pal, "label"))
        _, th = text_size(draw, "Ignored", fnt)
        field_y = y + int(12 * S) + th + int(8 * S)
        field_w = width - pad * 2 - int(40 * S)
        draw.rectangle(
            [x + pad, field_y, x + pad + field_w, field_y + int(26 * S)],
            fill=c(pal, "window"),
            outline=c(pal, "label"),
            width=STROKE,
        )
        draw_text(draw, (x + pad + int(8 * S), field_y + int(6 * S)), "com.example.app", font_dep(12 * S), c(pal, "secondary"))
        bx = x + pad + field_w + int(8 * S)
        draw.rectangle([bx, field_y + BEVEL, bx + int(28 * S), field_y + int(26 * S) + BEVEL], fill=c(pal, "bevel"))
        draw.rectangle([bx, field_y, bx + int(28 * S), field_y + int(26 * S)], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
        draw_text(draw, (bx + int(8 * S), field_y + int(4 * S)), "+", font_dep(14 * S), c(pal, "label"))
        return y + h
    if kind == "button":
        h = row_block_height(row, width)
        label = row["label"]
        fnt = font_dep(11 * S)
        tw, _ = text_size(draw, label, fnt)
        bw = tw + int(24 * S)
        bh = int(24 * S)
        by = y + int(12 * S)
        draw.rectangle([x + pad, by + BEVEL, x + pad + bw, by + bh + BEVEL], fill=c(pal, "bevel"))
        draw.rectangle([x + pad, by, x + pad + bw, by + bh], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
        draw_text(draw, (x + pad + int(12 * S), by + int(5 * S)), label, fnt, c(pal, "label"))
        return y + h
    return y + int(20 * S)


def draw_title_detail(draw, pal, title, detail, x, y, width) -> None:
    del width
    tf = font_dep(13 * S)
    draw_text(draw, (x, y), title, tf, c(pal, "label"))
    _, th = text_size(draw, title, tf)
    # Caption is SF Mono in the app — DejaVu here so ⇧/⌘ are real glyphs.
    draw_mixed_body(draw, (x, y + th + int(8 * S)), detail, 11 * S, c(pal, "secondary"))


def draw_switch(draw, pal, x, y, on: bool) -> None:
    w, h = int(34 * S), int(18 * S)
    fill = c(pal, "primary") if on else c(pal, "window")
    draw.rounded_rectangle([x, y, x + w, y + h], radius=int(2 * S), fill=fill, outline=c(pal, "control"), width=STROKE)
    knob = int(12 * S)
    pad = int(2 * S)
    kx = x + w - pad - knob if on else x + pad
    knob_fill = c(pal, "on_primary") if on else c(pal, "label")
    draw.rounded_rectangle([kx, y + (h - knob) / 2, kx + knob, y + (h + knob) / 2], radius=int(1 * S), fill=knob_fill)


def keycaps_width(draw, keys: list[str]) -> int:
    total = 0
    for key in keys:
        total += keycap_width(draw, key) + int(4 * S)
    return total - int(4 * S) + int(8 * S)


def keycap_width(draw, key: str) -> int:
    if key == "⇧":
        tw = int(11 * S)
    else:
        tw, _ = text_size(draw, key, font_dep(11 * S))
    return max(int(22 * S), tw + int(12 * S))


def draw_keycaps(draw, pal, keys: list[str], x: float, y: float) -> None:
    # Recorder chrome: fill well + 2pt border, keycaps inside.
    width = keycaps_width(draw, keys)
    h = int(26 * S) + int(8 * S)
    draw.rectangle([x, y - int(4 * S) + BEVEL, x + width, y - int(4 * S) + h + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle(
        [x, y - int(4 * S), x + width, y - int(4 * S) + h],
        fill=c(pal, "fill"),
        outline=c(pal, "control"),
        width=STROKE,
    )
    cx = x + int(4 * S)
    for key in keys:
        kw = keycap_width(draw, key)
        kh = int(22 * S)
        ky = y
        draw.rectangle([cx, ky + int(3 * S), cx + kw, ky + kh + int(3 * S)], fill=c(pal, "bevel"))
        draw.rectangle([cx, ky, cx + kw, ky + kh], fill=c(pal, "front"), outline=c(pal, "control"), width=STROKE)
        if key == "⇧":
            draw_shift(draw, cx + (kw - int(11 * S)) / 2, ky + (kh - int(11 * S)) / 2, int(11 * S), c(pal, "label"))
        else:
            fnt = font_dep(11 * S)
            tw, th = text_size(draw, key, fnt)
            draw_text(draw, (cx + (kw - tw) / 2, ky + (kh - th) / 2), key, fnt, c(pal, "label"))
        cx += kw + int(4 * S)


def draw_stepper(draw, pal, value: str, x: float, y: float) -> None:
    fnt = font_dep(12 * S)
    draw_text(draw, (x, y + int(3 * S)), value, fnt, c(pal, "label"))
    tw, _ = text_size(draw, value, fnt)
    bx = x + tw + int(8 * S)
    for i, glyph in enumerate(("−", "+")):
        gx = bx + i * int(22 * S)
        draw.rectangle([gx, y, gx + int(20 * S), y + int(20 * S)], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
        gf = font_dep(12 * S)
        gw, gh = text_size(draw, glyph, gf)
        draw_text(draw, (gx + (int(20 * S) - gw) / 2, y + (int(20 * S) - gh) / 2), glyph, gf, c(pal, "label"))


def draw_slider(draw, pal, fraction: float, value: str, x: float, y: float) -> None:
    track_w = int(120 * S)
    draw.rectangle([x, y, x + track_w, y + int(16 * S)], fill=c(pal, "fill"), outline=c(pal, "label"), width=STROKE)
    fill_w = max(2, int(track_w * fraction))
    draw.rectangle([x, y, x + fill_w, y + int(16 * S)], fill=c(pal, "label"))
    thumb = int(10 * S)
    tx = x + min(track_w - thumb, max(0, int(track_w * fraction) - thumb // 2))
    draw.rectangle([tx, y - int(1 * S), tx + thumb, y + int(17 * S)], fill=c(pal, "window"), outline=c(pal, "label"), width=STROKE)
    fnt = font_dep(11 * S)
    draw_text(draw, (x + track_w + int(8 * S), y), value, fnt, c(pal, "label"))


def draw_radio(draw, pal, x: float, y: float, selected: bool) -> None:
    r = int(7 * S)
    draw.ellipse([x, y, x + r * 2, y + r * 2], outline=c(pal, "label"), width=STROKE)
    if selected:
        inset = int(3 * S)
        draw.ellipse([x + inset, y + inset, x + r * 2 - inset, y + r * 2 - inset], fill=c(pal, "label"))


def mixed_width(draw, text: str, size: float) -> int:
    total = 0
    fnt = font_dep(size)
    buf = ""
    for ch in text:
        if ch in "⇧⌃⌫":
            if buf:
                total += text_size(draw, buf, fnt)[0]
                buf = ""
            total += int(size * 0.95)
        else:
            buf += ch
    if buf:
        total += text_size(draw, buf, fnt)[0]
    return total


def draw_mixed(draw, xy, text: str, size: float, fill) -> None:
    x, y = xy
    fnt = font_dep(size)
    buf = ""

    def flush() -> None:
        nonlocal x, buf
        if not buf:
            return
        draw_text(draw, (x, y), buf, fnt, fill)
        x += text_size(draw, buf, fnt)[0]
        buf = ""

    for ch in text:
        if ch == "⇧":
            flush()
            draw_shift(draw, x, y, size, fill)
            x += size * 0.95
        elif ch == "⌫":
            flush()
            draw_delete(draw, x, y, size, fill)
            x += size * 0.95
        elif ch == "⌃":
            flush()
            stroke = max(2, int(size * 0.14))
            draw.line(
                [(x + stroke, y + size * 0.68), (x + size / 2, y + size * 0.22), (x + size - stroke, y + size * 0.68)],
                fill=fill,
                width=stroke,
                joint="miter",
            )
            x += size * 0.95
        else:
            buf += ch
    flush()


def draw_mixed_body(draw, xy, text: str, size: float, fill) -> None:
    """System-mono caption: DejaVu has ⇧ ⌘ ⌥ ⌃ ⌫, matching SF Mono on the Mac."""
    draw_text(draw, xy, text, font_body(size), fill)


def paint_preview_edge(pal: dict) -> Image.Image:
    """List parked on the right screen edge; preview flips to the left."""
    screen_w, screen_h = int(1280 * S), int(800 * S)
    margin = int(24 * S)
    img = Image.new("RGB", (screen_w + margin * 2, screen_h + margin * 2), c(pal, "desk"))
    draw = ImageDraw.Draw(img)
    draw.rectangle([margin, margin, margin + screen_w, margin + screen_h], fill=c(pal, "screen"))
    # Visible-frame inset (menu bar).
    vis_top = margin + int(28 * S)
    vis_left = margin + int(8 * S)
    vis_right = margin + screen_w - int(8 * S)
    vis_bottom = margin + screen_h - int(8 * S)

    pw, ph = int(450 * S), int(480 * S)
    ox = vis_right - pw - BEVEL - int(8 * S)
    oy = vis_top + int(80 * S)
    draw_panel(draw, pal, ox, oy, pw, ph, selected=1)

    prev_w, prev_h = int(300 * S), int(260 * S)
    gutter = int(8 * S)
    # List midX is right of screen mid → preview prefers the left, then clamps.
    px = ox - gutter - prev_w - BEVEL
    if px < vis_left:
        px = ox + pw + gutter
    py = oy
    if py + prev_h > vis_bottom:
        py = vis_bottom - prev_h - BEVEL
    draw_preview(draw, pal, px, py, prev_w, prev_h, "https://github.com/bicrick/da-transcribuh")
    return img


def draw_search_glyph(draw, x, y, size, fill) -> None:
    stroke = max(2, int(size * 0.16))
    glass = size * 0.62
    draw.ellipse([x, y, x + glass, y + glass], outline=fill, width=stroke)
    draw.line([(x + glass * 0.78, y + glass * 0.78), (x + size - stroke, y + size - stroke)], fill=fill, width=stroke)


def draw_panel(draw, pal, ox, oy, pw, ph, selected: int) -> None:
    front = tuple(int(a * 0.95 + b * 0.05) for a, b in zip(c(pal, "front"), c(pal, "desk")))
    draw.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([ox, oy, ox + pw, oy + ph], fill=front, outline=c(pal, "label"), width=STROKE)
    hh = int(40 * S)
    draw.rectangle([ox + STROKE, oy + STROKE, ox + pw - STROKE, oy + hh], fill=c(pal, "fill"))
    draw.rectangle([ox, oy + hh, ox + pw, oy + hh + STROKE], fill=c(pal, "label"))
    draw_text(draw, (ox + int(12 * S), oy + int(12 * S)), "clipboard", font_dep(11 * S), c(pal, "secondary"))
    fx = ox + pw - int(12 * S) - int(220 * S)
    draw.rectangle([fx, oy + int(8 * S), fx + int(220 * S), oy + int(31 * S)], outline=c(pal, "label"), width=STROKE, fill=c(pal, "window"))
    draw_search_glyph(draw, fx + int(6 * S), oy + int(12 * S), int(11 * S), c(pal, "secondary"))
    draw_text(draw, (fx + int(22 * S), oy + int(12 * S)), "type to search…", font_dep(12 * S), c(pal, "secondary"))
    rows = [
        ("API_KEY=sk-live-••••", "⌘1"),
        ("https://github.com/bicrick/da-transcribuh", "⌘2"),
        ("func paste() { … }", "⌘3"),
        ("image", "⌘4"),
        ("meeting notes — q3", "⌘5"),
        ("island bevel invert", "⌘6"),
    ]
    y = oy + hh + STROKE
    for i, (text, shortcut) in enumerate(rows):
        rh = int(44 * S) if text == "image" else int(22 * S)
        if i == selected:
            bg = c(pal, "select")
        elif i == selected - 1:
            bg = c(pal, "hover")
        else:
            bg = front
        draw.rectangle([ox + STROKE, y, ox + pw - int(16 * S), y + rh], fill=bg)
        if text == "image":
            draw.rectangle(
                [ox + int(12 * S), y + int(2 * S), ox + int(12 * S) + int(48 * S), y + rh - int(2 * S)],
                fill=c(pal, "fill"),
                outline=c(pal, "hairline"),
                width=HAIR,
            )
        else:
            shown = text if len(text) < 42 else text[:20] + "…" + text[-16:]
            draw_text(draw, (ox + int(12 * S), y + int(4 * S)), shown, font_dep(12 * S), c(pal, "label"))
        sf = font_body(10 * S)
        sw, _ = text_size(draw, shortcut, sf)
        draw_text(draw, (ox + pw - int(28 * S) - sw, y + int(4 * S)), shortcut, sf, c(pal, "secondary"))
        y += rh
    track_x = ox + pw - int(12 * S)
    track_top = oy + hh
    track_bot = oy + ph - int(72 * S)
    draw.rectangle([track_x, track_top, track_x + int(10 * S), track_bot], outline=c(pal, "label"), width=STROKE, fill=c(pal, "window"))
    draw.rectangle([track_x, track_top + int(8 * S), track_x + int(10 * S), track_top + int(70 * S)], fill=c(pal, "label"))
    fy = oy + ph - int(72 * S)
    draw.rectangle([ox + STROKE, fy, ox + pw - STROKE, oy + ph - STROKE], fill=c(pal, "fill"))
    for i, (label, shortcut) in enumerate([("Clear", "⌥⌘⌫"), ("Preferences…", "⌘,"), ("Quit", "⌘Q")]):
        yy = fy + int(6 * S) + i * int(20 * S)
        draw_text(draw, (ox + int(12 * S), yy), label, font_dep(12 * S), c(pal, "label"))
        draw_mixed(draw, (ox + pw - int(90 * S), yy), shortcut, 11 * S, c(pal, "secondary"))


def draw_preview(draw, pal, px, py, prev_w, prev_h, title: str) -> None:
    front = tuple(int(a * 0.96 + b * 0.04) for a, b in zip(c(pal, "front"), c(pal, "desk")))
    draw.rectangle([px + BEVEL, py + BEVEL, px + prev_w + BEVEL, py + prev_h + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([px, py, px + prev_w, py + prev_h], fill=front, outline=c(pal, "label"), width=STROKE)
    shown = title if len(title) < 32 else title[:28] + "…"
    draw_text(draw, (px + int(12 * S), py + int(12 * S)), shown, font_dep(11 * S), c(pal, "label"))
    draw.rectangle([px + int(12 * S), py + int(36 * S), px + prev_w - int(12 * S), py + int(37 * S)], fill=c(pal, "hairline"))
    meta = [
        ("Application:", "Safari"),
        ("First copy time:", "Oct 22, 2026 at 9:41:02 PM"),
        ("Last copy time:", "Oct 22, 2026 at 9:44:18 PM"),
        ("Number of copies:", "3"),
    ]
    for i, (k, v) in enumerate(meta):
        yy = py + int(48 * S) + i * int(28 * S)
        draw_text(draw, (px + int(12 * S), yy), k, font_dep(10 * S), c(pal, "secondary"))
        draw_text(draw, (px + int(12 * S), yy + int(12 * S)), v, font_dep(10 * S), c(pal, "label"))
    draw_text(draw, (px + int(12 * S), py + prev_h - int(36 * S)), "Press ⌥P to pin.", font_dep(10 * S), c(pal, "secondary"))
    draw_mixed(draw, (px + int(12 * S), py + prev_h - int(20 * S)), "Press ⌥⌫ to delete.", 10 * S, c(pal, "secondary"))


def paint_selection_closeup(pal: dict) -> Image.Image:
    """Tight crop of the softened selection row (Ink.rowSelect, not a hard invert)."""
    scale = 2.0  # extra on top of S, so the row is a close-up
    row_h = int(22 * S * scale)
    pad = int(16 * S * scale)
    width = int(450 * S * scale)
    rows = [
        (False, "API_KEY=sk-live-••••", "⌘1"),
        (True, "https://github.com/bicrick/da-transcribuh", "⌘2"),
        (False, "func paste() { … }", "⌘3"),
    ]
    height = pad * 2 + row_h * len(rows) + STROKE * 2
    img = Image.new("RGB", (width + pad, height), c(pal, "desk"))
    draw = ImageDraw.Draw(img)
    ox, oy = pad // 2, pad // 2
    pw, ph = width, row_h * len(rows) + STROKE * 2
    draw.rectangle([ox + BEVEL, oy + BEVEL, ox + pw + BEVEL, oy + ph + BEVEL], fill=c(pal, "bevel"))
    draw.rectangle([ox, oy, ox + pw, oy + ph], fill=c(pal, "front"), outline=c(pal, "label"), width=STROKE)
    y = oy + STROKE
    for selected, text, shortcut in rows:
        bg = c(pal, "select") if selected else c(pal, "front")
        draw.rectangle([ox + STROKE, y, ox + pw - STROKE, y + row_h], fill=bg)
        fnt = font_dep(12 * S * scale * 0.5)
        shown = text if len(text) < 36 else text[:16] + "…" + text[-14:]
        draw_text(draw, (ox + int(12 * S * scale * 0.5), y + int(6 * S)), shown, fnt, c(pal, "label"))
        sf = font_body(10 * S * scale * 0.5)
        sw, _ = text_size(draw, shortcut, sf)
        draw_text(draw, (ox + pw - int(16 * S) - sw, y + int(6 * S)), shortcut, sf, c(pal, "secondary"))
        y += row_h
    return img


def assert_settings_uncropped(img: Image.Image, pal: dict) -> None:
    """Last painted content row must not sit on the image edge."""
    assert img.height > int(1400 * S), img.height
    # Bottom status bar is window-colored and fully inside the canvas.
    px = img.getpixel((10, img.height - 4))
    assert px == c(pal, "window"), px


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    MOCKS.mkdir(parents=True, exist_ok=True)
    assert SYMBOL.exists(), SYMBOL
    for name, pal in (("light", LIGHT), ("dark", DARK)):
        settings = paint_settings(pal)
        assert_settings_uncropped(settings, pal)
        edge = paint_preview_edge(pal)
        close = paint_selection_closeup(pal)
        for label, image in (
            ("settings", settings),
            ("preview-edge", edge),
            ("selection", close),
        ):
            image.save(OUT / f"clipboard-r2b-{label}-{name}-2x.png")
            image.save(MOCKS / f"clipboard-r2b-{label}-{name}.png")
            print(label, name, image.size)


if __name__ == "__main__":
    main()
