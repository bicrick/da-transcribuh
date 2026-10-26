#!/usr/bin/env python3
"""Render the README images in docs/readme/ (light + dark).

    pip install playwright pillow && python -m playwright install chromium
    python3 docs/readme/render.py

Everything is drawn from HTML/CSS with the site tokens and Departure Mono,
so re-running it is the whole pipeline. Nothing here ships in the app.
"""
from __future__ import annotations

import io
import pathlib

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FONT = (ROOT / "PromptAnnotator/Fonts/DepartureMono-Regular.otf").as_uri()
ICON = (ROOT / "PromptAnnotator/Assets.xcassets/AppIcon.appiconset/icon_1024.png").as_uri()

THEMES = {
    "light": dict(bg="#ffffff", ink="#000000", fill="#f0f0f0", front="#ffffff", hair="#c0c0c0",
                  sec="#666666", red="#ed1c24", bevel="#000000", sel="#e6e6e6"),
    "dark": dict(bg="#2c2c2e", ink="#f2f2f2", fill="#353538", front="#3a3a3d", hair="#4a4a4e",
                 sec="#a8a8ad", red="#ed1c24", bevel="#f2f2f2", sel="#454548"),
}

BASE_CSS = """
@font-face { font-family: dm; src: url('%(font)s'); }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { background: transparent; }
body { font-family: dm, monospace; color: var(--ink); -webkit-font-smoothing: antialiased; }
.key { display: inline-flex; align-items: center; justify-content: center; height: 34px; min-width: 38px;
  padding: 0 10px; font-size: 16.5px; background: var(--front); border: 2px solid var(--ink);
  box-shadow: 3px 3px 0 var(--bevel); }
.key.down { transform: translate(3px, 3px); box-shadow: 0 0 0 var(--bevel); }
"""


def vars_css(t: dict) -> str:
    return ":root{" + "".join(f"--{k}:{v};" for k, v in t.items()) + "}"


# ---------------------------------------------------------------- header
HEADER = """<!doctype html><html><head><style>%(base)s %(vars)s
#c { display: inline-flex; align-items: center; gap: 28px; padding: 12px 16px 12px 12px; }
img { width: 132px; height: 132px; display: block; }
h1 { font-weight: normal; font-size: 55px; line-height: 1; letter-spacing: 0; }
</style></head><body><div id="c"><img src="%(icon)s"><h1>da transcribuh</h1></div></body></html>"""

# ---------------------------------------------------------------- features
FEATURES = """<!doctype html><html><head><style>%(base)s %(vars)s
#c { display: flex; gap: 24px; padding: 4px 8px 10px 4px; }
.card { width: 296px; background: var(--front); border: 2px solid var(--ink); box-shadow: 3px 3px 0 var(--bevel); }
.art { height: 128px; border-bottom: 2px solid var(--ink); background: var(--fill); position: relative;
  display: flex; align-items: center; justify-content: center; }
.txt { padding: 14px 16px 16px; }
.n { color: var(--sec); font-size: 11px; }
h3 { font-weight: normal; font-size: 22px; margin: 6px 0 8px; }
p { font-size: 13.75px; color: var(--sec); line-height: 1.45; }
.chip { display: flex; align-items: center; gap: 10px; padding: 8px 12px; background: var(--front);
  border: 2px solid var(--ink); font-size: 13.75px; box-shadow: 3px 3px 0 var(--bevel); }
.dot { width: 10px; height: 10px; background: var(--red); }
.sel { position: absolute; left: 58px; top: 26px; width: 150px; height: 72px; border: 2px dashed var(--ink);
  background: color-mix(in srgb, var(--red) 10%%, transparent); }
.cross { position: absolute; left: 200px; top: 90px; width: 18px; height: 18px; }
.cross:before, .cross:after { content: ""; position: absolute; background: var(--red); }
.cross:before { left: 8px; top: 0; width: 2px; height: 18px; }
.cross:after { top: 8px; left: 0; height: 2px; width: 18px; }
.xy { position: absolute; left: 218px; top: 104px; font-size: 11px; background: var(--ink); color: var(--bg);
  padding: 1px 4px; white-space: nowrap; }
.list { width: 210px; background: var(--front); border: 2px solid var(--ink); box-shadow: 3px 3px 0 var(--bevel); }
.row { display: flex; justify-content: space-between; padding: 5px 8px; font-size: 11px; }
.row + .row { border-top: 1px solid var(--hair); }
.row.on { background: var(--sel); }
.row span:last-child { color: var(--sec); }
</style></head><body><div id="c">
 <div class="card"><div class="art"><div class="chip"><span class="dot"></span>whisper · on this mac</div></div>
  <div class="txt"><div class="n">01</div><h3>on device</h3><p>nothing gets uploaded.<br>no account. no cloud.</p></div></div>
 <div class="card"><div class="art"><div class="sel"></div><div class="cross"></div><div class="xy">454, 255</div></div>
  <div class="txt"><div class="n">02</div><h3>grab the screen</h3><p>shift + drag while u talk.<br>the pic pastes too.</p></div></div>
 <div class="card"><div class="art"><div class="list">
   <div class="row on"><span>ok so the save button…</span><span>⌘1</span></div>
   <div class="row"><span>example.com/spec</span><span>⌘2</span></div>
   <div class="row"><span>brb getting food</span><span>⌘3</span></div></div></div>
  <div class="txt"><div class="n">03</div><h3>clipboard history</h3><p>⌘ shift C.<br>everything u copied.</p></div></div>
</div></body></html>"""

# ---------------------------------------------------------------- demo gif
SAID = "ok so the save button should go on the left"
DEMO = """<!doctype html><html><head><style>%(base)s %(vars)s
#c { width: 720px; height: 380px; background: var(--bg); border: 2px solid var(--ink); position: relative; overflow: hidden; }
.bar { height: 36px; display: flex; align-items: center; gap: 8px; padding: 0 12px; border-bottom: 2px solid var(--ink);
  background: var(--fill); font-size: 13.75px; }
.sq { width: 10px; height: 10px; border: 1px solid var(--ink); }
.bar .t { margin-left: 10px; color: var(--sec); }
.msg { position: absolute; left: 24px; top: 58px; font-size: 13.75px; line-height: 1.5; }
.msg b { font-weight: normal; }
.msg .who { color: var(--sec); }
.box { position: absolute; left: 24px; right: 24px; bottom: 58px; height: 46px; border: 2px solid var(--ink);
  background: var(--front); display: flex; align-items: center; padding: 0 12px; font-size: 13.75px; }
.ph { color: var(--sec); }
.caret { display: inline-block; width: 2px; height: 16px; background: var(--ink); margin-left: 1px; vertical-align: -3px; }
.toast { position: absolute; right: 36px; bottom: 116px; font-size: 11px; color: var(--sec); }
.foot { position: absolute; left: 24px; bottom: 18px; display: flex; align-items: center; gap: 12px; font-size: 13.75px; }
.steps { display: flex; gap: 4px; } .steps i { width: 22px; height: 8px; border: 1px solid var(--ink); }
.steps i.on { background: var(--red); border-color: var(--red); }
.foot .s { color: var(--sec); }
.stage { position: absolute; left: 0; right: 0; top: 118px; height: 120px; }
.keys { position: absolute; left: 50%%; top: 30px; transform: translateX(-50%%); display: flex; gap: 8px; }
.island { position: absolute; left: 50%%; top: 14px; width: 330px; height: 46px; margin-left: -165px;
  background: #3a3a3d; border: 2px solid #f2f2f2; display: flex; align-items: center; gap: 12px; padding: 0 14px;
  color: #f2f2f2; font-size: 13.75px; box-shadow: 3px 3px 0 var(--bevel); }
.island .rec { flex: none; width: 12px; height: 12px; background: var(--red); }
.island .tm { color: #a8a8ad; width: 34px; }
.wave { display: flex; align-items: center; gap: 3px; height: 24px; flex: 1; }
.wave i { width: 3px; background: #f2f2f2; }
.cnt { border: 2px solid #f2f2f2; font-size: 11px; padding: 0 5px; height: 20px; display: flex; align-items: center; }
.live { position: absolute; left: 0; right: 0; top: 78px; text-align: center; font-size: 16.5px; }
</style></head><body><div id="c">
 <div class="bar"><span class="sq" style="background:#ed1c24"></span><span class="sq" style="background:#fff200"></span>
  <span class="sq" style="background:#22b14c"></span><span class="t"># design</span></div>
 <div class="msg"><span class="who">sam ·</span> where should the save button go?</div>
 <div class="stage"><div class="keys" id="keys"><span class="key" id="k1">⌥</span><span class="key" id="k2">space</span></div>
  <div class="island" id="isl"><span class="rec"></span><span class="tm" id="tm">0:00</span><span class="wave" id="wave"></span>
   <span class="cnt">0</span></div>
  <div class="live" id="live"></div></div>
 <div class="toast" id="toast">pasted · 0.3s</div>
 <div class="box" id="box"></div>
 <div class="foot"><span class="steps" id="steps"><i></i><i></i><i></i></span><span id="cap"></span></div>
</div>
<script>
const SAID = %(said)r.split(' ');
const wave = document.getElementById('wave');
for (let i = 0; i < 34; i++) wave.appendChild(document.createElement('i'));
const ease = x => 1 - Math.pow(1 - Math.min(Math.max(x, 0), 1), 3);
function render(t) {
  const $ = id => document.getElementById(id);
  const step = t < 1.3 ? 0 : t < 4.9 ? 1 : 2;
  const caps = [['hit the key.', 'a lil island pops up.'], ['say stuff.', 'words show up live.'], ['hit it again.', 'it pastes where ur cursor is.']];
  $('cap').innerHTML = caps[step][0] + ' <span class="s">' + caps[step][1] + '</span>';
  [...$('steps').children].forEach((el, i) => el.className = i <= step ? 'on' : '');
  const keysOn = t < 1.3 || (t >= 4.9 && t < 5.9);
  const down = (t > 0.7 && t < 1.15) || (t > 5.3 && t < 5.75);
  $('keys').style.opacity = keysOn ? 1 : 0;
  $('k1').className = $('k2').className = 'key' + (down ? ' down' : '');
  const islIn = ease((t - 1.3) / 0.25), islOut = t >= 4.9 ? 0 : 1;
  $('isl').style.opacity = islIn * islOut;
  $('isl').style.transform = 'scale(' + (0.9 + 0.1 * islIn) + ')';
  const rec = Math.max(0, t - 1.3);
  $('tm').textContent = '0:0' + Math.min(9, Math.floor(rec));
  [...wave.children].forEach((b, i) => {
    const talking = t > 1.6 && t < 4.6;
    const h = talking ? 4 + Math.abs(Math.sin(i * 1.7 + t * 9) * Math.cos(i * 0.6 - t * 5)) * 20 : 3;
    b.style.height = Math.round(h) + 'px';
  });
  const n = Math.max(0, Math.min(SAID.length, Math.floor((t - 1.7) / 0.28) + 1));
  $('live').textContent = t >= 1.6 && t < 4.9 ? SAID.slice(0, t < 1.7 ? 0 : n).join(' ') : '';
  const pasted = t >= 5.75;
  $('box').innerHTML = pasted ? SAID.join(' ') + '<span class="caret"></span>' : '<span class="ph">message #design</span>';
  $('toast').style.opacity = pasted && t < 7.6 ? 1 : 0;
}
</script></body></html>"""


def snap(palette: list[int], theme: dict) -> list[int]:
    # median cut drifts flat fills (#fff comes out #fcfcfc); pull near-token entries back exact
    tokens = [tuple(int(v[i:i + 2], 16) for i in (1, 3, 5)) for v in theme.values()]
    out = list(palette)
    for i in range(0, len(out) - 2, 3):
        c = out[i:i + 3]
        best = min(tokens, key=lambda t: sum((a - b) ** 2 for a, b in zip(c, t)))
        if sum((a - b) ** 2 for a, b in zip(c, best)) <= 75:
            out[i:i + 3] = best
    return out


def load(pg, tpl: str, theme: dict) -> None:
    # file:// fonts and images only load from a file:// page, so go through a temp file
    tmp = HERE / ".render.html"
    tmp.write_text(tpl % dict(base=BASE_CSS % dict(font=FONT), vars=vars_css(theme), icon=ICON, said=SAID))
    pg.goto(tmp.as_uri())
    pg.evaluate("document.fonts.ready")
    pg.wait_for_timeout(200)
    tmp.unlink()


def main() -> None:
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name, theme in THEMES.items():
            pg = browser.new_page(device_scale_factor=2, viewport={"width": 1000, "height": 600})
            # header + features: transparent PNGs, so they sit on any GitHub background
            for tpl, out in ((HEADER, "header"), (FEATURES, "features")):
                load(pg, tpl, theme)
                pg.locator("#c").screenshot(path=str(HERE / f"{out}-{name}.png"), omit_background=True)
            # demo: opaque frames, assembled into a looping GIF
            load(pg, DEMO, theme)
            fps, dur = 12.5, 8.4
            frames = []
            for i in range(int(fps * dur)):
                pg.evaluate(f"render({i / fps})")
                png = pg.locator("#c").screenshot()
                frames.append(Image.open(io.BytesIO(png)).convert("RGB"))
            # one shared palette from a strip of key frames keeps flat fills exact
            keys = [frames[k] for k in range(0, len(frames), 12)]
            strip = Image.new("RGB", (keys[0].width, keys[0].height * len(keys)))
            for k, f in enumerate(keys):
                strip.paste(f, (0, k * f.height))
            pal = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
            pal.putpalette(snap(pal.getpalette(), theme))
            q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
            q[0].save(HERE / f"demo-{name}.gif", save_all=True, append_images=q[1:],
                      duration=int(1000 / fps), loop=0, optimize=True, disposal=1)
            pg.close()
        browser.close()
    for f in sorted(HERE.glob("*.[pg][ni][gf]")):
        print(f"{f.stat().st_size / 1024:8.1f} KB  {f.name}")


if __name__ == "__main__":
    main()
