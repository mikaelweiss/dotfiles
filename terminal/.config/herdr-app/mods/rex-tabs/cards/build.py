"""Builds Rex-style program cards from Herdr's program table.

Each card's glyph is the public brand mark listed in glyphs.json (sources and
licenses in LICENSES.md), else Herdr's own glyph.

Run after a Herdr update to pick up new programs:
    python3 ~/.config/herdr-app/mods/rex-tabs/cards/build.py
"""
import base64
import json
import math
import re
import subprocess
from pathlib import Path

CARDS = Path(__file__).resolve().parent
HOME = CARDS.parents[2]
APP = Path.home() / "Applications/Herdr.app/Contents/MacOS/Herdr"

GLYPHS = json.loads((CARDS / "glyphs.json").read_text())

# Rex draws Claude as a white glyph on an orange card.
OVERRIDES = {"claude": {"tile": "#e56a40", "color": "#ffffff", "tint": True}}


def program_table():
    text = subprocess.run(["strings", "-n", "20", str(APP)], capture_output=True, text=True).stdout
    table = {}
    for line in text.splitlines():
        if re.match(r'^\s*"[a-z0-9._-]+": \{"name":"[^"]*","icon":"icons/', line):
            try:
                table.update(json.loads("{" + line.strip().rstrip(",") + "}"))
            except json.JSONDecodeError:
                pass
    return table


def squircle(x, y, w, h, radius, smoothing=0.6):
    """Apple-style continuous corners, after figma-squircle's corner smoothing."""
    budget = min(w, h) / 2
    r = min(radius, budget)
    smoothing = min(smoothing, budget / r - 1)
    p = min((1 + smoothing) * r, budget)
    arc_measure = 90 * (1 - smoothing)
    arc = math.sin(math.radians(arc_measure / 2)) * r * math.sqrt(2)
    alpha = (90 - arc_measure) / 2
    beta = 45 * smoothing
    c = r * math.tan(math.radians(alpha / 2)) * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - arc - c - d) / 3
    a = 2 * b
    n = lambda v: f"{v:.3f}"
    return (
        f"M {n(x + w - p)} {n(y)} "
        f"c {n(a)} 0 {n(a + b)} 0 {n(a + b + c)} {n(d)} a {n(r)} {n(r)} 0 0 1 {n(arc)} {n(arc)} c {n(d)} {n(c)} {n(d)} {n(b + c)} {n(d)} {n(a + b + c)} "
        f"L {n(x + w)} {n(y + h - p)} "
        f"c 0 {n(a)} 0 {n(a + b)} {n(-d)} {n(a + b + c)} a {n(r)} {n(r)} 0 0 1 {n(-arc)} {n(arc)} c {n(-c)} {n(d)} {n(-(b + c))} {n(d)} {n(-(a + b + c))} {n(d)} "
        f"L {n(x + p)} {n(y + h)} "
        f"c {n(-a)} 0 {n(-(a + b))} 0 {n(-(a + b + c))} {n(-d)} a {n(r)} {n(r)} 0 0 1 {n(-arc)} {n(-arc)} c {n(-d)} {n(-c)} {n(-d)} {n(-(b + c))} {n(-d)} {n(-(a + b + c))} "
        f"L {n(x)} {n(y + p)} "
        f"c 0 {n(-a)} 0 {n(-(a + b))} {n(d)} {n(-(a + b + c))} a {n(r)} {n(r)} 0 0 1 {n(arc)} {n(-arc)} c {n(c)} {n(-d)} {n(b + c)} {n(-d)} {n(a + b + c)} {n(-d)} Z"
    )


def mix(hex_color, target, amount):
    rgb = [int(hex_color[i : i + 2], 16) for i in (1, 3, 5)]
    end = 255 if target == "white" else 0
    return "#" + "".join(f"{round(c + (end - c) * amount):02x}" for c in rgb)


def raster(path):
    data = base64.b64encode(path.read_bytes()).decode()
    return f'<image x="15" y="9" width="34" height="34" href="data:image/png;base64,{data}"/>'


def glyph(svg_text, tint, color):
    root = re.search(r"<svg\b([^>]*)>", svg_text, re.S)
    body = svg_text[root.end() : svg_text.rindex("</svg>")]
    attrs = re.sub(r'\s(width|height|style|class|role)="[^"]*"', "", root.group(1))
    if tint:
        # Single-color glyphs take the card's color, however they paint.
        body = re.sub(r'(fill|stroke)="(?!none|url\()[^"]*"', rf'\1="{color}"', body)
        attrs = re.sub(r'(fill|stroke)="(?!none|url\()[^"]*"', rf'\1="{color}"', attrs)
    # Rex's cards are 5:4, so the glyph sits centered in a 64x52 card.
    return f'<g fill="{color if tint else "currentColor"}" color="{color}"><svg x="15" y="9" width="34" height="34"{attrs}>{body}</svg></g>'


def card(key, program):
    tile = program["tile"]
    dark = sum(int(tile[i : i + 2], 16) for i in (1, 3, 5)) < 150
    top = mix(tile, "white", 0.2 if dark else 0.12)
    bottom = mix(tile, "black", 0.0 if dark else 0.05)
    color = program.get("color", "#ffffff")
    public = GLYPHS.get(key)
    if public and public["file"].endswith(".png"):
        art = raster(CARDS / public["file"])
    elif public:
        art = glyph((CARDS / public["file"]).read_text(), public["tint"], color)
    else:
        art = glyph((HOME / program["icon"]).read_text(), program.get("tint"), color)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 52" width="64" height="52">
<defs>
<linearGradient id="fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.5"/><stop offset="0.35" stop-color="#ffffff" stop-opacity="0.16"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.08"/></linearGradient>
</defs>
<path d="{squircle(0.75, 0.75, 62.5, 50.5, 13.25)}" fill="none" stroke="#000000" stroke-opacity="0.4" stroke-width="1.5"/>
<path d="{squircle(1.5, 1.5, 61, 49, 12.5)}" fill="url(#fill)"/>
<path d="{squircle(2.25, 2.25, 59.5, 47.5, 11.75)}" fill="none" stroke="url(#edge)" stroke-width="1.5"/>
{art}
</svg>
'''


def main():
    table = program_table()
    for key, program in table.items():
        program = {**program, **OVERRIDES.get(key, {})}
        if not program.get("tile") or not (HOME / program["icon"]).exists():
            continue
        (CARDS / f"{key}.svg").write_text(card(key, program))
    print(f"{len(list(CARDS.glob('*.svg')))} cards, {sum(k in GLYPHS for k in table)} with a public glyph")


main()
