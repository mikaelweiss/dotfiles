"""Builds Rex-style program cards from Herdr's program table.

Each card's glyph is the public brand mark listed in glyphs.json (sources and
licenses in LICENSES.md), else Herdr's own glyph.

Run after a Herdr update to pick up new programs:
    python3 ~/.config/herdr-app/mods/rex-tabs/cards/build.py
"""
import base64
import json
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
<rect x="0.75" y="0.75" width="62.5" height="50.5" rx="13.25" fill="none" stroke="#000000" stroke-opacity="0.4" stroke-width="1.5"/>
<rect x="1.5" y="1.5" width="61" height="49" rx="12.5" fill="url(#fill)"/>
<rect x="2.25" y="2.25" width="59.5" height="47.5" rx="11.75" fill="none" stroke="url(#edge)" stroke-width="1.5"/>
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
